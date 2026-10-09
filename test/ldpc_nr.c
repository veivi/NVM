/*
 * ldpc_nr.c -- 5G NR LDPC with the real base graphs: lifting, encoder, AWGN
 * channel, and decoding with the AVU-style kernel from ldpc_ref.c.
 *
 * Build (ldpc_ref.c and nr_bg_tables.h must be in the same directory):
 *
 *   gcc -std=c11 -O2 -Wall -Wextra ldpc_nr.c -o ldpc_nr -lm
 *
 * Run:
 *   ./ldpc_nr                       self-test (encoder for every Z, decoder battery)
 *   ./ldpc_nr --verify-csv bg1.csv bg2.csv
 *                                   diff the embedded tables against Sionna's
 *                                   5G_bg1.csv / 5G_bg2.csv (or any CSV in that format)
 *   ./ldpc_nr -bg 1 -z 384 -snr 1.5 -frames 20 -iters 20 -v 16 -q 8
 *                                   one custom simulation point
 *   add --edge-table to a custom run to dump the kernel's per-edge constants
 *
 * What this file does:
 *
 *   1. Lifting.  A base-graph entry has a shift coefficient V for each of the
 *      8 lifting sets i_LS; for lifting size Z the circulant shift is
 *      V[i_LS(Z)] mod Z.  Convention (same as ldpc_ref.c): check lane i of an
 *      edge with shift s touches codeword element (i + s) mod Z, i.e. the
 *      identity matrix with its columns rotated right by s.
 *
 *   2. Encoding.  Systematic: columns 0..kb-1 are the information bits
 *      (kb = 22 for BG1, 10 for BG2).  The first four rows form the "core"
 *      with a dual-diagonal parity part in columns kb..kb+3:
 *         - summing the four core rows cancels parity columns 2..4 (each
 *           appears twice with equal shift) and leaves one circulant on the
 *           first parity column, which is solved directly;
 *         - the other three core parities follow by back-substitution;
 *         - each extension row l >= 4 has an identity at column kb+l, so its
 *           parity is just the XOR of its other terms.
 *      Nothing is hard-wired to BG1/BG2: the structure is checked as it is
 *      used and the encoder returns an error code if the table doesn't fit.
 *
 *   3. Channel.  Raw LDPC only: no CRC, segmentation, filler bits, rate
 *      matching or interleaving.  The first two columns (2Z systematic bits)
 *      are punctured, as in NR (LLR = 0 at the receiver); every other column
 *      of the mother code is sent over BPSK + AWGN, so the code rate is
 *      kb/(nb-2) = 1/3 (BG1) or 1/5 (BG2).  LLRs are quantized to int8.
 *
 *   4. Decoding.  ref_decode() (plain layered min-sum, golden model) and
 *      kern_decode() (the packed/rotated kernel) from ldpc_ref.c run on the
 *      same frame and must agree bit for bit.
 */

#define main ldpc_ref_main        /* reuse the decoders, drop its test main() */
#include "ldpc_ref.c"
#undef main

#include <math.h>
#include <time.h>
#include "nr_bg_tables.h"

typedef uint8_t bit_t;

/* ===================================================================== */
/*  1. Lifting sets and lifted code                                       */
/* ===================================================================== */

static const int LIFT_SET[8][9] = {
    {  2,  4,  8, 16,  32,  64, 128, 256, 0 },
    {  3,  6, 12, 24,  48,  96, 192, 384, 0 },
    {  5, 10, 20, 40,  80, 160, 320,   0, 0 },
    {  7, 14, 28, 56, 112, 224,   0,   0, 0 },
    {  9, 18, 36, 72, 144, 288,   0,   0, 0 },
    { 11, 22, 44, 88, 176, 352,   0,   0, 0 },
    { 13, 26, 52, 104, 208,  0,   0,   0, 0 },
    { 15, 30, 60, 120, 240,  0,   0,   0, 0 },
};

static int lifting_set(int Z)
{
    for (int s = 0; s < 8; s++)
        for (int k = 0; LIFT_SET[s][k]; k++)
            if (LIFT_SET[s][k] == Z) return s;
    return -1;
}

typedef struct {
    int bg, Z, set, nb, mb, kb;
    code_t code;                      /* lifted shifts, decoder format */
} nrcode_t;

static int nr_code_init(nrcode_t *n, int bg, int Z)
{
    if ((bg != 1 && bg != 2) || (n->set = lifting_set(Z)) < 0) return -1;
    n->bg = bg; n->Z = Z;
    const nr_bg_edge_t *tab = bg == 1 ? NR_BG1 : NR_BG2;
    const int ne = bg == 1 ? NR_BG1_EDGES : NR_BG2_EDGES;
    n->nb = bg == 1 ? NR_BG1_NB : NR_BG2_NB;
    n->mb = bg == 1 ? NR_BG1_MB : NR_BG2_MB;
    n->kb = bg == 1 ? NR_BG1_KB : NR_BG2_KB;
    n->code = code_new(n->nb, n->mb, Z);
    for (int e = 0; e < ne; e++)
        n->code.shift[tab[e].row][tab[e].col] = tab[e].v[n->set] % Z;
    return 0;
}

/* ===================================================================== */
/*  2. Encoder                                                            */
/* ===================================================================== */

static bit_t X[MAXC][MAXZ];           /* codeword, one row per base column */

static void xor_shifted(bit_t *dst, const bit_t *src, int s, int Z)   /* dst ^= P_s * src */
{
    for (int i = 0; i < Z; i++) dst[i] ^= src[(i + s) % Z];
}

/* x[0..kb-1] hold the information bits on entry; fills the parity columns.
 * Returns 0, or a negative code if the table structure is not what the
 * encoder expects (never happens for the NR graphs). */
static int nr_encode(const nrcode_t *n, bit_t (*x)[MAXZ])
{
    const int Z = n->Z, kb = n->kb, mb = n->mb, nb = n->nb;
    const code_t *K = &n->code;
    static bit_t lam[4][MAXZ];
    bit_t rhs[MAXZ], sum[MAXZ];

    /* lambda_l = information part of core row l */
    memset(lam, 0, sizeof lam);
    for (int l = 0; l < 4; l++)
        for (int c = 0; c < kb; c++)
            if (K->shift[l][c] >= 0) xor_shifted(lam[l], x[c], K->shift[l][c], Z);

    /* sum of the four core rows: columns kb+1..kb+3 must cancel, column kb
     * must leave exactly one circulant (shifts cancel in pairs mod 2) */
    int s_first = 0;
    for (int j = 0; j < 4; j++) {
        int sh[4], m = 0;
        for (int l = 0; l < 4; l++) {
            int s = K->shift[l][kb + j];
            if (s < 0) continue;
            int f = -1;
            for (int q = 0; q < m; q++) if (sh[q] == s) { f = q; break; }
            if (f >= 0) { sh[f] = sh[m - 1]; m--; } else sh[m++] = s;
        }
        if (j == 0) { if (m != 1) return -1; s_first = sh[0]; }
        else if (m != 0) return -2;
    }
    for (int i = 0; i < Z; i++) sum[i] = lam[0][i] ^ lam[1][i] ^ lam[2][i] ^ lam[3][i];
    for (int j = 0; j < Z; j++) x[kb][j] = sum[((j - s_first) % Z + Z) % Z];   /* P_s p = sum */

    /* back-substitution: row k introduces parity column kb+1+k */
    for (int k = 0; k < 3; k++) {
        memcpy(rhs, lam[k], (size_t)Z);
        for (int m = 0; m <= k; m++)
            if (K->shift[k][kb + m] >= 0) xor_shifted(rhs, x[kb + m], K->shift[k][kb + m], Z);
        for (int m = k + 2; m < 4; m++)
            if (K->shift[k][kb + m] >= 0) return -3;
        int sn = K->shift[k][kb + 1 + k];
        if (sn < 0) return -4;
        for (int j = 0; j < Z; j++) x[kb + 1 + k][j] = rhs[((j - sn) % Z + Z) % Z];
    }

    /* extension rows: identity on their own parity column */
    for (int l = 4; l < mb; l++) {
        bit_t *p = x[kb + l];
        memset(p, 0, (size_t)Z);
        for (int c = 0; c < kb + 4; c++)
            if (K->shift[l][c] >= 0) xor_shifted(p, x[c], K->shift[l][c], Z);
        if (K->shift[l][kb + l] != 0) return -5;
        for (int c = kb + 4; c < nb; c++)
            if (c != kb + l && K->shift[l][c] >= 0) return -6;
    }

    printf("Code: kb=%d nb=%d mb=%d Z=%d\n", kb, nb, mb, Z);

    for(int i = 0; i < kb; i++)
      for(int k = 0; k < Z; k++)
	printf("%d", x[i][k]);

    printf(" | ");
      
    for(int i = kb; i < nb; i++)
      for(int k = 0; k < Z; k++)
	printf("%d", x[i][k]);
    
    printf("\n");
    
    return 0;
}

static int syndrome_weight(const nrcode_t *n, bit_t (*x)[MAXZ])
{
    int bad = 0;
    for (int l = 0; l < n->mb; l++)
        for (int i = 0; i < n->Z; i++) {
            int p = 0;
            for (int c = 0; c < n->nb; c++) {
                int s = n->code.shift[l][c];
                if (s >= 0) p ^= x[c][(i + s) % n->Z];
            }
            bad += p;
        }
    return bad;
}

static int test_encoder_all_sizes(void)
{
    int tested = 0, bad = 0;
    for (int bg = 1; bg <= 2; bg++)
        for (int s = 0; s < 8; s++)
            for (int k = 0; LIFT_SET[s][k]; k++) {
                const int Z = LIFT_SET[s][k];
                nrcode_t n;
                if (nr_code_init(&n, bg, Z)) { bad++; continue; }
                memset(X, 0, sizeof X);
                for (int c = 0; c < n.kb; c++)
		  for (int i = 0; i < Z; i++) X[c][i] =(bit_t)((rnd() >> 9) & 1);
                int rc = nr_encode(&n, X);
                int w  = rc ? -1 : syndrome_weight(&n, X);
                X[0][0] ^= 1;                                   /* corrupt one bit */
                int w2 = syndrome_weight(&n, X);
                tested++;
                if (rc || w || !w2) {
                    bad++;
                    printf("  BG%d Z=%d (set %d): encode rc=%d, syndrome weight %d, after 1 flip %d\n",
                           bg, Z, s, rc, w, w2);
                }
            }
    printf("encoder: %d (base graph, Z) combinations, %d failures"
           " (each: H*c = 0, and a flipped bit is detected)\n", tested, bad);
    return bad;
}

/* ===================================================================== */
/*  3. Channel and one simulation point                                   */
/* ===================================================================== */

static double uni(void) { return ((double)rnd() + 0.5) / 4294967296.0; }
static double gauss(void)
{
    double u1 = uni(), u2 = uni();
    return sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2);
}

static int pick_V(int Z)             /* largest V <= 16 that the kernel layout allows, 0 if none */
{
    if (Z % 4) return 0;
    for (int v = 16; v >= 1; v--) if ((Z / 4) % v == 0) return v;
    return 0;
}

typedef struct {
    int frames, ref_frame_err, valid, kern_ran, kern_mismatch;
    long info_bits, bit_err;
    double secs_ref, secs_kern;
} trial_t;

static void run_trial(int bg, int Z, double ebn0_db, int frames, int iters,
                      int V, double qscale, int edge_dump, trial_t *T)
{
    nrcode_t n;
    if (nr_code_init(&n, bg, Z)) { fprintf(stderr, "bad (bg, Z) = (%d, %d)\n", bg, Z); exit(2); }
    memset(T, 0, sizeof *T);
    if (!V) V = pick_V(Z);
    const double rate   = (double)n.kb / (n.nb - 2);
    const double sigma2 = 1.0 / (2.0 * rate * pow(10.0, ebn0_db / 10.0));
    const double sigma  = sqrt(sigma2);
    static bit_t U[MAXC][MAXZ];

    for (int f = 0; f < frames; f++) {
        memset(X, 0, sizeof X);
        for (int c = 0; c < n.kb; c++)
	  for (int i = 0; i < Z; i++) X[c][i] = U[c][i] =  (c+i/3) & 1; // (bit_t)((rnd() >> 9) & 1);
        int rc = nr_encode(&n, X);
        if (rc || syndrome_weight(&n, X)) { fprintf(stderr, "encoder failure rc=%d\n", rc); exit(3); }

        for (int c = 0; c < n.nb; c++)
            for (int i = 0; i < Z; i++) {
                int q = 0;                                     /* punctured columns: LLR 0 */
                if (c >= 2) {
                    double y = (X[c][i] ? -1.0 : 1.0) + sigma * gauss();
                    double l = 2.0 * y / sigma2 * qscale;
                    q = sat8((int)lround(l));
                }
                FA[c][i] = FB[c][i] = (llr_t)q;
            }

        clock_t t0 = clock();
        ref_decode(&n.code, FA, iters);
        clock_t t1 = clock();
        T->secs_ref += (double)(t1 - t0) / CLOCKS_PER_SEC;

        if (V && kern_decode(&n.code, V, FB, iters, edge_dump && f == 0) == 0) {
            T->secs_kern += (double)(clock() - t1) / CLOCKS_PER_SEC;
            T->kern_ran++;
            if (!frames_equal(&n.code, FA, FB)) T->kern_mismatch++;
        }

        long errs = 0;
        for (int c = 0; c < n.kb; c++)
            for (int i = 0; i < Z; i++) errs += ((FA[c][i] < 0) != (U[c][i] != 0));
        T->bit_err += errs;
        T->info_bits += (long)n.kb * Z;
        T->ref_frame_err += errs != 0;
        T->valid += syndrome_ok(&n.code, FA);
        if (getenv("NR_DBG")) {
            long zero = 0, viol = 0;
            for (int c = 0; c < n.nb; c++) for (int i = 0; i < Z; i++) zero += FA[c][i] == 0;
            for (int l = 0; l < n.code.mb; l++) for (int i = 0; i < Z; i++) {
                int p = 0;
                for (int c = 0; c < n.nb; c++)
                    if (n.code.shift[l][c] >= 0) p ^= (FA[c][(i + n.code.shift[l][c]) % Z] < 0);
                viol += p; }
            fprintf(stderr, "dbg frame %d: L==0 count %ld, violated checks %ld\n", f, zero, viol);
        }
        T->frames++;
    }
}

static void report(int bg, int Z, double snr, int iters, int V, const trial_t *T)
{
    nrcode_t n; nr_code_init(&n, bg, Z);
    printf("BG%d Z=%-3d (set %d, K=%-5d N=%-5d) Eb/N0 %4.1f dB, %2d it: "
           "FER %d/%d  BER %.1e  valid cw %d/%d  ",
           bg, Z, n.set, n.kb * Z, (n.nb - 2) * Z, snr, iters,
           T->ref_frame_err, T->frames, (double)T->bit_err / (double)T->info_bits,
           T->valid, T->frames);
    if (T->kern_ran) printf("kernel(V=%d)==ref: %s\n", V ? V : pick_V(Z),
                            T->kern_mismatch ? "MISMATCH" : "yes");
    else             printf("kernel: n/a (needs Z%%4==0)\n");
}

/* ===================================================================== */
/*  4. Check the embedded tables against a CSV file                       */
/* ===================================================================== */

static int verify_csv(const char *path, const nr_bg_edge_t *tab, int ne, const char *name)
{
    FILE *fp = fopen(path, "r");
    if (!fp) { perror(path); return -1; }
    char line[512];
    int row = -1, lines = 0, matched = 0, differ = 0, unknown = 0;
    static char seen[MAXL][MAXC];
    memset(seen, 0, sizeof seen);

    while (fgets(line, sizeof line, fp)) {
        char *fld[16]; int nf = 0;
        for (char *q = line; *q; q++) if (*q == '\r' || *q == '\n') *q = 0;
        fld[nf++] = line;
        for (char *p = line; *p; p++)
            if (*p == ';') { *p = 0; if (nf < 16) fld[nf++] = p + 1; }
        if (nf < 10) continue;
        if (!fld[1][0] || strspn(fld[1], "0123456789") != strlen(fld[1])) continue;   /* header */
        if (fld[0][0]) row = atoi(fld[0]);
        int col = atoi(fld[1]);
        lines++;
        int e = -1;
        for (int k = 0; k < ne; k++) if (tab[k].row == row && tab[k].col == col) { e = k; break; }
        if (e < 0) { unknown++; printf("  %s: CSV has (%d,%d), not in the embedded table\n", name, row, col); continue; }
        int same = 1;
        for (int s = 0; s < 8; s++) if (atoi(fld[2 + s]) != tab[e].v[s]) same = 0;
        seen[row][col] = 1;
        if (same) matched++;
        else { differ++; printf("  %s: values differ at row %d col %d\n", name, row, col); }
    }
    fclose(fp);
    int missing = 0;
    for (int k = 0; k < ne; k++) if (!seen[tab[k].row][tab[k].col]) missing++;
    printf("%s: CSV has %d edges; %d identical, %d differ, %d unknown to the table, %d table edges missing from CSV\n",
           name, lines, matched, differ, unknown, missing);
    return differ + unknown + missing;
}

/* ===================================================================== */
/*  5. Main                                                               */
/* ===================================================================== */

static void usage(void)
{
    printf("usage: ldpc_nr                          self-test\n"
           "       ldpc_nr --verify-csv bg1.csv bg2.csv\n"
           "       ldpc_nr -bg 1|2 -z Z -snr dB [-frames N] [-iters N] [-v V] [-q scale] [--edge-table]\n");
}

static int battery(void)
{
    static const struct { int bg, Z; double snr; int frames, iters; } B[] = {
        { 1, 384, 0.0, 2, 20 }, { 1, 384, 2.0, 3, 20 },
        { 1, 256, 2.0, 2, 20 }, { 1, 192, 2.0, 2, 20 }, { 1, 320, 2.0, 2, 20 },
        { 1, 224, 2.0, 2, 20 }, { 1, 288, 2.0, 2, 20 }, { 1, 352, 2.0, 2, 20 },
        { 1, 208, 2.0, 2, 20 }, { 1, 240, 2.0, 2, 20 },
        { 2, 384, 0.5, 2, 20 }, { 2, 384, 2.5, 3, 20 },
        { 2, 208, 2.5, 2, 20 }, { 2, 240, 2.5, 2, 20 }, { 2, 352, 2.5, 2, 20 },
        { 1, 15, 2.5, 3, 20 }, { 2, 13, 3.0, 3, 20 },
    };
    int bad = 0;
    for (unsigned k = 0; k < sizeof B / sizeof B[0]; k++) {
        trial_t T;
        run_trial(B[k].bg, B[k].Z, B[k].snr, B[k].frames, B[k].iters, 0, 3.0, 0, &T);
        report(B[k].bg, B[k].Z, B[k].snr, B[k].iters, 0, &T);
        bad += T.kern_mismatch;
    }
    return bad;
}

int main(int argc, char **argv)
{
    int bg = 0, Z = 0, frames = 10, iters = 20, V = 0, edge_dump = 0;
    double snr = 1.5, qscale = 3.0;
    g_mag_max = 63;          /* see comment at g_mag_max in ldpc_ref.c */

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--verify-csv") && i + 2 < argc)
            return verify_csv(argv[i + 1], NR_BG1, NR_BG1_EDGES, "BG1") +
                   verify_csv(argv[i + 2], NR_BG2, NR_BG2_EDGES, "BG2") != 0;
        else if (!strcmp(argv[i], "-bg") && i + 1 < argc)     bg = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-z") && i + 1 < argc)      Z = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-snr") && i + 1 < argc)    snr = atof(argv[++i]);
        else if (!strcmp(argv[i], "-frames") && i + 1 < argc) frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-iters") && i + 1 < argc)  iters = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v") && i + 1 < argc)      V = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-q") && i + 1 < argc)      qscale = atof(argv[++i]);
        else if (!strcmp(argv[i], "-m") && i + 1 < argc)      g_mag_max = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge-table"))            edge_dump = 1;
        else { usage(); return 2; }
    }

    if (bg && Z) {                                           /* one custom point */
        trial_t T;
        run_trial(bg, Z, snr, frames, iters, V, qscale, edge_dump, &T);
        report(bg, Z, snr, iters, V, &T);
        printf("time per frame: ref %.3f s, kernel model %.3f s\n",
               T.secs_ref / T.frames, T.kern_ran ? T.secs_kern / T.kern_ran : 0.0);
        return T.kern_mismatch != 0;
    }

    printf("BG1: %dx%d, %d edges, kb=%d, rate 1/3 after puncturing 2 columns\n"
           "BG2: %dx%d, %d edges, kb=%d, rate 1/5 after puncturing 2 columns\n\n",
           NR_BG1_MB, NR_BG1_NB, NR_BG1_EDGES, NR_BG1_KB,
           NR_BG2_MB, NR_BG2_NB, NR_BG2_EDGES, NR_BG2_KB);
    int bad = test_encoder_all_sizes();
    printf("\ndecoder battery (golden model vs kernel model, AWGN, int8 LLRs):\n");
    bad += battery();
    printf(bad ? "FAIL\n" : "PASS\n");
    return bad != 0;
}
