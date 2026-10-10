/*
 * l5_acq.c -- GPS L5 acquisition, C reference model.
 *
 *   gcc -std=gnu11 -O2 -Wall -Wextra l5_acq.c -o l5_acq -lm
 *
 * Contents
 *   1. L5 I5/Q5 PRN code generator (IS-GPS-705 3.3.2) and Neuman-Hofman codes
 *   2. radix-2 FFT, N = 16384 (one millisecond at fs = 16.384 MHz)
 *   3. signal synthesiser: I5 (data + NH10) + Q5 (pilot, NH20), Doppler incl. code Doppler,
 *      complex AWGN with a stated C/N0, optional 1..3-bit quantisation
 *   4. acquisition: parallel code-phase search, FFT based
 *        - 2 ms sliding window (32768-point FFT, bins 500 Hz) against a 1 ms replica padded
 *          with zeros: every lag sees one whole code epoch, so the NH20 sign is clean
 *        - one forward FFT per (window, sub-bin carrier offset), shared by all Doppler bins
 *          and all PRNs; steps that are multiples of 500 Hz are circular shifts of the
 *          spectrum (no extra FFT), finer steps use D sub-bin offsets
 *        - per Doppler bin and window: spectrum x conj(replica spectrum) -> one inverse FFT
 *        - coherent integration of L ms with NH20 wipe-off (20 hypotheses), then
 *          non-coherent accumulation of M such blocks
 *        - code-Doppler compensation of the ms-to-ms code-phase drift
 *        - detection metric: peak / best peak more than 2 chips away (PSR)
 *   5. self-test, single-shot acquisition, and a Monte-Carlo sensitivity sweep
 *
 * Complex baseband input, 16384 samples per ms, sample n <-> chip floor(n*10230/16384).
 * Everything is double precision; this is the algorithmic golden model, a fixed-point
 * version is the next step.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <complex.h>
#include <time.h>

#include "l5_prn_table.h"

#define PI        3.14159265358979323846
#define NS        16384            /* samples per ms */
#define NF        (2 * NS)         /* FFT size: 2 ms window, 500 Hz bins */
#define CODE_LEN  10230
#define FS        16.384e6
#define FC        10.23e6
#define FL5       1176.45e6

typedef double complex cpx;

/* ===================================================================== */
/*  1. Codes                                                              */
/* ===================================================================== */

static const int TAPS_A[4] = { 9, 10, 12, 13 };                /* 1 + x9 + x10 + x12 + x13 */
static const int TAPS_B[8] = { 1, 3, 4, 6, 7, 8, 12, 13 };     /* 1 + x + x3 + x4 + x6 + x7 + x8 + x12 + x13 */

/* NH codes as bits: 0 -> +1, 1 -> -1 */
static const int NH10[10] = { 0, 0, 0, 0, 1, 1, 0, 1, 0, 1 };
static const int NH20[20] = { 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0 };

/* stage i+1 lives in s[i]; chip out = stage 13 = s[12]; feedback enters stage 1 */
static void lfsr_step(int *s, const int *taps, int nt)
{
    int fb = 0;
    for (int i = 0; i < nt; i++) fb ^= s[taps[i] - 1];
    memmove(s + 1, s, 12 * sizeof(int));
    s[0] = fb;
}

static void state_from_string(int *s, const char *str)
{
    for (int i = 0; i < 13; i++) s[i] = str[i] == '1';
}

/* out[i] = +1 for code bit 0, -1 for code bit 1 */
static void l5_code(int prn, int q, signed char *out)
{
    int a[13], b[13], b0[13];
    for (int i = 0; i < 13; i++) a[i] = 1;
    state_from_string(b0, q ? L5_PRN[prn - 1].sQ : L5_PRN[prn - 1].sI);
    memcpy(b, b0, sizeof b);
    for (int i = 0; i < CODE_LEN; i++) {
        if (i == 8190) for (int k = 0; k < 13; k++) a[k] = 1;      /* XA short-cycled */
        if (i == 8191) memcpy(b, b0, sizeof b);                    /* XB wraps */
        out[i] = (a[12] ^ b[12]) ? -1 : 1;
        lfsr_step(a, TAPS_A, 4);
        lfsr_step(b, TAPS_B, 8);
    }
}

/* ===================================================================== */
/*  2. FFT                                                                */
/* ===================================================================== */

static cpx tw[NF / 2];
static int brev[NF];

static void fft_init(void)
{
    for (int k = 0; k < NF / 2; k++) tw[k] = cexp(-2.0 * PI * I * k / NF);
    for (int i = 0; i < NF; i++) {
        int r = 0;
        for (int b = 0; b < 15; b++) if (i & (1 << b)) r |= 1 << (14 - b);
        brev[i] = r;
    }
}

/* in place; inv != 0: inverse transform including the 1/N */
static void fft(cpx *a, int inv)
{
    if (inv) for (int i = 0; i < NF; i++) a[i] = conj(a[i]);
    for (int i = 0; i < NF; i++) if (i < brev[i]) { cpx t = a[i]; a[i] = a[brev[i]]; a[brev[i]] = t; }
    for (int len = 2; len <= NF; len <<= 1) {
        int half = len >> 1, step = NF / len;
        for (int i = 0; i < NF; i += len)
            for (int k = 0; k < half; k++) {
                cpx t = tw[k * step] * a[i + k + half];
                a[i + k + half] = a[i + k] - t;
                a[i + k] += t;
            }
    }
    if (inv) for (int i = 0; i < NF; i++) a[i] = conj(a[i]) * (1.0 / NF);
}

/* ===================================================================== */
/*  3. Signal synthesis                                                   */
/* ===================================================================== */

static uint64_t rs = 88172645463325252ULL;
static uint64_t rnd64(void) { rs ^= rs >> 12; rs ^= rs << 25; rs ^= rs >> 27; return rs * 2685821657736338717ULL; }
static double uni(void) { return ((rnd64() >> 11) + 0.5) * (1.0 / 9007199254740992.0); }
static double gauss(void)
{
    static int have = 0; static double g2;
    if (have) { have = 0; return g2; }
    double u = uni(), v = uni(), r = sqrt(-2.0 * log(u));
    g2 = r * sin(2.0 * PI * v); have = 1;
    return r * cos(2.0 * PI * v);
}

static int posmod(long a, int m) { int r = (int)(a % m); return r < 0 ? r + m : r; }
static long floordiv(long a, long m) { long q = a / m; return (a % m != 0 && ((a < 0) != (m < 0))) ? q - 1 : q; }

typedef struct {
    int    prn;
    double cn0;        /* dB-Hz, total L5 power (I5 + Q5); < 0: noise only */
    double dop;        /* Hz */
    double tau;        /* code delay in chips, may be fractional */
    double phase;      /* rad */
    int    nh_start;   /* NH epoch counter at code epoch 0 (any integer >= 1) */
} gnss_sig_t;

/* Mid-rise quantiser with unit-variance-optimal step; the noise has sigma^2 = 0.5 per component */
static double quant(double v, int bits)
{
    if (bits <= 0) return v;
    const double sg = sqrt(0.5);
    if (bits == 1) return v < 0 ? -1.0 : 1.0;
    double step = (bits == 2 ? 0.996 : 0.586) * sg;
    int top = (1 << (bits - 1)) - 1;
    int k = (int)floor(v / step);
    if (k > top) k = top;
    if (k < -top - 1) k = -top - 1;
    return k + 0.5;
}

/* x has nms*NS samples; noise power: 1 per complex sample (so N0 = 1/FS) */
static void synth(cpx *x, int nms, const gnss_sig_t *s, int bits)
{
    static signed char cI[CODE_LEN], cQ[CODE_LEN];
    static int dbits[256];
    double A = s->cn0 >= 0 ? sqrt(pow(10.0, s->cn0 / 10.0) / FS) : 0.0;
    if (A > 0) { l5_code(s->prn, 0, cI); l5_code(s->prn, 1, cQ); }
    for (int i = 0; i < 256; i++) dbits[i] = (int)(rnd64() >> 63);
    for (long n = 0; n < (long)nms * NS; n++) {
        cpx v = 0;
        if (A > 0) {
            double chipf = (double)n * (10230.0 / 16384.0) * (1.0 + s->dop / FL5) - s->tau;
            long ci = (long)floor(chipf);
            long e = floordiv(ci, CODE_LEN);
            int c = (int)(ci - e * CODE_LEN);
            long ea = e + s->nh_start;
            int sI = cI[c] * (NH10[posmod(ea, 10)] ? -1 : 1) * (dbits[posmod(floordiv(ea, 10), 256)] ? -1 : 1);
            int sQ = cQ[c] * (NH20[posmod(ea, 20)] ? -1 : 1);
            v = A * (sI + I * sQ) * (1.0 / sqrt(2.0)) * cexp(I * (2.0 * PI * s->dop * (double)n / FS + s->phase));
        }
        v += sqrt(0.5) * (gauss() + I * gauss());
        x[n] = quant(creal(v), bits) + I * quant(cimag(v), bits);
    }
}

/* ===================================================================== */
/*  4. Acquisition                                                        */
/* ===================================================================== */

typedef struct {
    int    prn;
    char   ch;         /* 'I' or 'Q'; L > 1 needs 'Q' (pilot) */
    int    L;          /* coherent ms */
    int    M;          /* non-coherent blocks; ms used = L*M */
    double dmax;       /* search +-dmax Hz */
    double dstep;      /* Doppler step Hz, 500/dstep must be an integer */
    int    comp;       /* compensate code Doppler */
} cfg_t;

typedef struct { double v, nl, nr; int tau, j, kf, h; } peak_t;

typedef struct {
    double dop, tau_s, tau_chips, peak, second, psr, pmr;
    int    nh, found;
    long   n_fwd, n_inv;
} res_t;

#define KPK 3
#define PKW 4      /* samples between stored peaks of one row */

static void row_peaks(const double *row, peak_t *out)
{
    unsigned char mask[NS]; memset(mask, 0, sizeof mask);
    for (int k = 0; k < KPK; k++) {
        int bi = -1; double bv = -1;
        for (int t = 0; t < NS; t++) if (!mask[t] && row[t] > bv) { bv = row[t]; bi = t; }
        out[k].v = bv; out[k].tau = bi;
        out[k].nl = row[(bi - 1) & (NS - 1)]; out[k].nr = row[(bi + 1) & (NS - 1)];
        for (int d = -PKW; d <= PKW; d++) mask[(bi + d) & (NS - 1)] = 1;
    }
}

static void acquire(const cpx *x, const cfg_t *c, res_t *R)
{
    int ms = c->L * c->M;
    int D = (int)lround(500.0 / c->dstep);       /* sub-bin carrier offsets per 500 Hz FFT bin */
    double sub = 500.0 / D;
    int H = c->L > 1 ? 20 : 1;
    memset(R, 0, sizeof *R);

    static signed char code[CODE_LEN];
    l5_code(c->prn, c->ch == 'Q', code);
    /* replica: one ms of code, zero padded to 2 ms, so that each lag in [0,NS) sees exactly one
       whole code epoch of the 2 ms window (no tail/head sign mixing from the NH code) */
    cpx *Cc = calloc(NF, sizeof(cpx));
    for (int n = 0; n < NS; n++) Cc[n] = code[(long)n * CODE_LEN / NS];
    fft(Cc, 0);
    for (int n = 0; n < NF; n++) Cc[n] = conj(Cc[n]);

    cpx    *X   = malloc((size_t)ms * NF * sizeof(cpx));
    cpx    *r   = malloc((size_t)ms * NS * sizeof(cpx));
    cpx    *tmp = malloc(NF * sizeof(cpx));
    double *acc = malloc((size_t)H * NS * sizeof(double));
    size_t pcap = 1024, pn = 0;
    peak_t *pk  = malloc(pcap * sizeof(peak_t));
    double sum = 0; long cnt = 0;

    for (int j = 0; j < D; j++) {
        double phi = j * sub;
        for (int k = 0; k < ms; k++) {
            cpx *xk = X + (size_t)k * NF;                 /* window k = ms k and k+1 */
            for (int n = 0; n < NF; n++)
                xk[n] = x[(size_t)k * NS + n] * cexp(-2.0 * PI * I * phi * ((double)k * NS + n) / FS);
            fft(xk, 0); R->n_fwd++;
        }
        int kf0 = (int)ceil((-c->dmax - phi) / 500.0), kf1 = (int)floor((c->dmax - phi) / 500.0);
        for (int kf = kf0; kf <= kf1; kf++) {
            double f = kf * 500.0 + phi;
            double drift = c->comp ? (double)NS * f / FL5 : 0.0;       /* samples per ms */
            for (int k = 0; k < ms; k++) {
                const cpx *xk = X + (size_t)k * NF;
                for (int m = 0; m < NF; m++) tmp[m] = xk[(m + kf) & (NF - 1)] * Cc[m];
                fft(tmp, 1); R->n_inv++;
                long sk = lround(k * drift);
                double sgn = ((kf * k) & 1) ? -1.0 : 1.0;   /* 500 Hz * k ms = k/2 cycles of carrier phase */
                cpx *rk = r + (size_t)k * NS;
                for (int t = 0; t < NS; t++) rk[t] = sgn * tmp[(t - sk) & (NS - 1)];
            }
            memset(acc, 0, (size_t)H * NS * sizeof(double));
            for (int g = 0; g < c->M; g++)
                for (int h = 0; h < H; h++) {
                    double *a = acc + (size_t)h * NS;
                    for (int t = 0; t < NS; t++) {
                        cpx S = 0;
                        for (int l = 0; l < c->L; l++) {
                            int k = g * c->L + l;
                            S += (H > 1 && NH20[(h + k) % 20] ? -1.0 : 1.0) * r[(size_t)k * NS + t];
                        }
                        a[t] += creal(S) * creal(S) + cimag(S) * cimag(S);
                    }
                }
            for (int h = 0; h < H; h++) {
                const double *a = acc + (size_t)h * NS;
                for (int t = 0; t < NS; t++) sum += a[t];
                cnt += NS;
                if (pn + KPK > pcap) { pcap *= 2; pk = realloc(pk, pcap * sizeof(peak_t)); }
                row_peaks(a, pk + pn);
                for (int k = 0; k < KPK; k++) { pk[pn + k].j = j; pk[pn + k].kf = kf; pk[pn + k].h = h; }
                pn += KPK;
            }
        }
    }

    if (pn == 0) { free(Cc); free(X); free(r); free(tmp); free(acc); free(pk); return; }
    size_t bi = 0;
    for (size_t i = 1; i < pn; i++) if (pk[i].v > pk[bi].v) bi = i;
    const peak_t *b = &pk[bi];
    double second = 0;
    for (size_t i = 0; i < pn; i++) {
        int d = abs(pk[i].tau - b->tau); if (d > NS / 2) d = NS - d;
        if (d > 2.0 * NS / CODE_LEN + 1 && pk[i].v > second) second = pk[i].v;
    }
    double den = b->nl + b->nr - 2.0 * b->v, off = 0;       /* parabolic interpolation */
    if (den != 0) off = 0.5 * (b->nl - b->nr) / den;
    if (off > 0.5) off = 0.5;
    if (off < -0.5) off = -0.5;
    R->dop = b->kf * 500.0 + b->j * sub;
    R->tau_s = b->tau + off;
    R->tau_chips = R->tau_s * CODE_LEN / NS;
    R->nh = b->h;
    R->peak = b->v; R->second = second;
    R->psr = second > 0 ? b->v / second : 1e9;
    R->pmr = b->v / (sum / (double)cnt);
    R->found = 1;
    free(Cc); free(X); free(r); free(tmp); free(acc); free(pk);
}

/* ===================================================================== */
/*  5. Tests, single shot, sweep                                          */
/* ===================================================================== */

static int fails = 0;
#define CHECK(cond, ...) do { if (!(cond)) { printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); fails++; } } while (0)

static void test_table(void)
{
    int ok = 0;
    for (int p = 0; p < 63; p++)
        for (int q = 0; q < 2; q++) {
            int s[13]; for (int i = 0; i < 13; i++) s[i] = 1;
            int n = q ? L5_PRN[p].nQ : L5_PRN[p].nI;
            for (int i = 0; i < n; i++) lfsr_step(s, TAPS_B, 8);
            int e[13]; state_from_string(e, q ? L5_PRN[p].sQ : L5_PRN[p].sI);
            ok += memcmp(s, e, sizeof s) == 0;
        }
    printf("table: %d/126 (advance, initial state) pairs consistent\n", ok);
    CHECK(ok == 126, "table inconsistent");

    int a[13], b[13], pa = 0, pb = 0;
    for (int i = 0; i < 13; i++) a[i] = b[i] = 1;
    for (int n = 1; n <= 9000; n++) {
        lfsr_step(a, TAPS_A, 4); lfsr_step(b, TAPS_B, 8);
        int ia = 1, ib = 1;
        for (int i = 0; i < 13; i++) { ia &= a[i]; ib &= b[i]; }
        if (ia && !pa) pa = n;
        if (ib && !pb) pb = n;
    }
    printf("register periods: XA %d, XB %d (both must be 8191)\n", pa, pb);
    CHECK(pa == 8191 && pb == 8191, "LFSR period");
}

static void test_codes(void)
{
    static signed char c[4][CODE_LEN];
    int prns[2] = { 1, 63 };
    int idx = 0;
    for (int pi = 0; pi < 2; pi++) for (int q = 0; q < 2; q++) l5_code(prns[pi], q, c[idx++]);
    for (int i = 0; i < 4; i++) {
        int sum = 0, side = 0, cross = 0;
        for (int k = 0; k < CODE_LEN; k++) sum += c[i][k];
        for (int lag = 1; lag < CODE_LEN; lag++) {
            int ac = 0, cc = 0;
            for (int k = 0; k < CODE_LEN; k++) {
                ac += c[i][k] * c[i][(k + lag) % CODE_LEN];
                cc += c[i][k] * c[(i + 1) % 4][(k + lag) % CODE_LEN];
            }
            if (abs(ac) > side) side = abs(ac);
            if (abs(cc) > cross) cross = abs(cc);
        }
        printf("code %d (PRN %d %c5): sum %+d, max autocorr sidelobe %d, max cross-corr with next %d (peak %d)\n",
               i, prns[i / 2], (i & 1) ? 'Q' : 'I', sum, side, cross, CODE_LEN);
        CHECK(abs(sum) < 400 && side < 700 && cross < 700, "code statistics");
    }
}

static void test_fft(void)
{
    static cpx a[NF], b[NF];
    for (int i = 0; i < NF; i++) a[i] = b[i] = gauss() + I * gauss();
    fft(a, 0);
    double e = 0;
    for (int k = 0; k < 6; k++) {
        int kk = (k * 2731 + 5) % NF; cpx s = 0;
        for (int n = 0; n < NF; n++) s += b[n] * cexp(-2.0 * PI * I * (double)((long)kk * n % NF) / NF);
        e = fmax(e, cabs(s - a[kk]));
    }
    fft(a, 1);
    double e2 = 0;
    for (int i = 0; i < NF; i++) e2 = fmax(e2, cabs(a[i] - b[i]));
    printf("fft: max error vs direct DFT %.2e, round trip %.2e\n", e, e2);
    CHECK(e < 1e-6 && e2 < 1e-9, "fft");
}

static res_t one_shot(const gnss_sig_t *s, const cfg_t *c, int bits, int verbose)
{
    int ms = c->L * c->M;
    cpx *x = malloc((size_t)(ms + 1) * NS * sizeof(cpx));
    synth(x, ms + 1, s, bits);
    res_t R; acquire(x, c, &R);
    free(x);
    if (verbose)
        printf("  est: Doppler %+8.1f Hz  code delay %9.3f chips  NH start %2d  PSR %.2f  peak/mean %.1f\n",
               R.dop, R.tau_chips, R.nh, R.psr, R.pmr);
    return R;
}

static void test_acq(void)
{
    gnss_sig_t s = { 7, 45.0, 1730.0, 4321.4, 0.7, 13 };
    cfg_t c = { 7, 'Q', 1, 4, 5000.0, 500.0, 1 };
    printf("acquisition, strong signal (PRN 7, 45 dB-Hz, true Doppler %+.0f Hz, delay %.1f chips, NH start %d):\n",
           s.dop, s.tau, s.nh_start % 20);
    res_t R = one_shot(&s, &c, 0, 1);
    CHECK(fabs(R.dop - s.dop) <= 500.0, "Doppler error");
    CHECK(fabs(R.tau_chips - s.tau) <= 1.0, "code phase error");
    CHECK(R.psr > 1.5, "PSR");
    double psr_right = R.psr;

    c.prn = 8;
    printf("  same samples searched with PRN 8:\n");
    res_t W = one_shot(&s, &c, 0, 1);
    CHECK(W.psr < psr_right, "wrong PRN not rejected");

    printf("coherent 4 ms x 3 blocks with NH20 wipe-off, 46 dB-Hz, 2-bit samples:\n");
    gnss_sig_t s2 = { 7, 46.0, -2210.0, 900.6, 2.0, 27 };
    cfg_t c2 = { 7, 'Q', 4, 3, 5000.0, 125.0, 1 };
    res_t R2 = one_shot(&s2, &c2, 2, 1);
    printf("  true: Doppler %+.0f Hz  delay %.1f chips  NH start (mod 20) %d\n", s2.dop, s2.tau, s2.nh_start % 20);
    CHECK(fabs(R2.dop - s2.dop) <= 125.0, "Doppler error (coherent)");
    CHECK(fabs(R2.tau_chips - s2.tau) <= 1.0, "code phase error (coherent)");
    int nh_true = s2.nh_start % 20;
    CHECK(R2.nh == nh_true, "NH phase");
}

static int cmp_d(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }

static void sweep(int prn, int L, int M, double dstep, int bits, int trials, const double *cn0s, int ncn0, int comp)
{
    cfg_t c = { prn, 'Q', L, M, 5000.0, dstep, comp };
    double *h0 = malloc(trials * sizeof(double));
    clock_t t0 = clock();
    for (int i = 0; i < trials; i++) {
        gnss_sig_t n0 = { prn, -1.0, 0, 0, 0, 1 };
        res_t R = one_shot(&n0, &c, bits, 0);
        h0[i] = R.psr;
    }
    qsort(h0, trials, sizeof(double), cmp_d);
    double thr = h0[trials - 1];
    printf("L=%d ms coherent x M=%d non-coherent (%d ms), Doppler step %.0f Hz, %d-bit samples, %d trials/point\n",
           L, M, L * M, dstep, bits, trials);
    printf("noise only: PSR median %.2f, max %.2f  -> threshold %.2f (Pfa <~ %.0f%%)\n",
           h0[trials / 2], thr, thr, 100.0 / trials);
    for (int k = 0; k < ncn0; k++) {
        int det = 0, ok = 0; double eavg = 0;
        for (int i = 0; i < trials; i++) {
            gnss_sig_t s = { prn, cn0s[k], (uni() - 0.5) * 8000.0, uni() * CODE_LEN, uni() * 2 * PI, 1 + (int)(rnd64() % 40) };
            res_t R = one_shot(&s, &c, bits, 0);
            int good = fabs(R.dop - s.dop) <= dstep && fabs(R.tau_chips - s.tau) <= 1.0;
            if (R.psr > thr) { det++; if (good) ok++; }
            if (good) eavg += 1;
        }
        printf("  C/N0 %5.1f dB-Hz: detected %3d%%  (detected and correct %3d%%)\n",
               cn0s[k], 100 * det / trials, 100 * ok / trials);
        (void)eavg;
    }
    printf("  (%.1f s)\n", (double)(clock() - t0) / CLOCKS_PER_SEC);
    free(h0);
}

static void usage(void)
{
    fprintf(stderr,
        "usage: l5_acq                  self-test\n"
        "       l5_acq --acq [opts]     one acquisition on a synthetic signal\n"
        "       l5_acq --sweep [opts]   detection probability vs C/N0\n"
        "  opts: -prn N -cn0 dBHz -dop Hz -tau chips -nh N -L ms -M blocks -ch I|Q\n"
        "        -dmax Hz -dstep Hz -bits 0..3 -nocomp -trials N -cn0list a,b,c -seed N\n");
}

int main(int argc, char **argv)
{
    int mode = 0, prn = 7, L = 1, M = 10, bits = 0, trials = 40, comp = 1, nh = 5;
    double cn0 = 40, dop = 1234.0, tau = 3000.3, dmax = 5000.0, dstep = -1;
    char ch = 'Q';
    double cn0s[32]; int ncn0 = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--acq")) mode = 1;
        else if (!strcmp(a, "--sweep")) mode = 2;
        else if (!strcmp(a, "-nocomp")) comp = 0;
        else if (i + 1 < argc && !strcmp(a, "-prn")) prn = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-cn0")) cn0 = atof(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-dop")) dop = atof(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-tau")) tau = atof(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-nh")) nh = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-L")) L = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-M")) M = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-ch")) ch = argv[++i][0];
        else if (i + 1 < argc && !strcmp(a, "-dmax")) dmax = atof(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-dstep")) dstep = atof(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-bits")) bits = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-trials")) trials = atoi(argv[++i]);
        else if (i + 1 < argc && !strcmp(a, "-seed")) rs ^= strtoull(argv[++i], 0, 10) * 0x9E3779B97F4A7C15ULL;
        else if (i + 1 < argc && !strcmp(a, "-cn0list")) {
            char *p = strtok(argv[++i], ",");
            while (p && ncn0 < 32) { cn0s[ncn0++] = atof(p); p = strtok(0, ","); }
        } else { usage(); return 2; }
    }
    if (prn < 1 || prn > 63 || L < 1 || M < 1 || (L > 1 && ch != 'Q')) { usage(); return 2; }
    if (dstep < 0) dstep = 500.0 / L;
    if (fabs(500.0 / dstep - lround(500.0 / dstep)) > 1e-9) { fprintf(stderr, "500/dstep must be an integer\n"); return 2; }

    fft_init();

    if (mode == 1) {
        gnss_sig_t s = { prn, cn0, dop, tau, 0.5, nh };
        cfg_t c = { prn, ch, L, M, dmax, dstep, comp };
        printf("truth: PRN %d  C/N0 %.1f dB-Hz  Doppler %+.1f Hz  delay %.2f chips  NH start %d\n",
               prn, cn0, dop, tau, nh % 20);
        clock_t t0 = clock();
        int ms = L * M;
        cpx *x = malloc((size_t)(ms + 1) * NS * sizeof(cpx));
        synth(x, ms + 1, &s, bits);
        res_t R; acquire(x, &c, &R);
        free(x);
        printf("found: Doppler %+.1f Hz  delay %.2f chips  NH start %d  PSR %.2f  peak/mean %.1f\n",
               R.dop, R.tau_chips, R.nh, R.psr, R.pmr);
        printf("work: %ld forward + %ld inverse 32768-point FFTs for %d ms of data (%.1f s here)\n",
               R.n_fwd, R.n_inv, ms, (double)(clock() - t0) / CLOCKS_PER_SEC);
        return 0;
    }
    if (mode == 2) {
        if (!ncn0) { double d[] = { 30, 32, 34, 36, 38, 40 }; memcpy(cn0s, d, sizeof d); ncn0 = 6; }
        sweep(prn, L, M, dstep, bits, trials, cn0s, ncn0, comp);
        return 0;
    }

    printf("== L5 acquisition reference: self-test ==\n");
    test_table();
    test_fft();
    test_codes();
    test_acq();
    printf(fails ? "\nFAILED (%d)\n" : "\nPASS\n", fails);
    return fails != 0;
}
