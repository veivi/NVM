/*
 * ldpc_ref.c -- bit-exact C reference for the AVU-assisted layered
 * normalized min-sum LDPC decoder kernel (int8 LLRs, alpha = 3/4).
 *
 * Contains two decoders and a self-checking test harness:
 *
 *   ref_decode()   plain textbook layered min-sum in the canonical frame.
 *                  This is the golden model.
 *   kern_decode()  the kernel as it would run on the machine: packed
 *                  quarter-interleaved columns, doubled + byte-rotated
 *                  buffers, rotation by word offset + uniform byte rotate,
 *                  ping-pong column buffers, slice loop, and the AVU ops
 *                  (LRESET / LCMP / LMSG) as explicit functions.
 *
 * Both must agree bit for bit. Build and run:
 *
 *   gcc -std=c11 -O2 -Wall -Wextra ldpc_ref.c -o ldpc_ref && ./ldpc_ref
 *   ./ldpc_ref -d        also dumps the edge table of the toy code
 *
 * Conventions (all of them matter when you port this to assembly):
 *
 *  - Code: QC base matrix, shift[l][c] >= 0 is a circulant, < 0 is empty.
 *    In the check frame of an edge with shift s, lane i reads canonical
 *    element (i + s) mod Z.
 *  - LLRs: int8, saturated symmetrically to [-127, 127]. Positive = bit 0.
 *    Sign of 0 is "positive". Magnitudes are 0..127.
 *  - Message scaling: SCALE34(m) = (3*m) >> 2.  Compile with -DSCALE_ALT to
 *    use m - (m >> 2) instead (they round differently; pick what your
 *    hardware does and keep both decoders on the same one).
 *  - Packing (needs Z % 4 == 0, Qp = Z/4): word w of a column holds
 *    { x[w], x[w+Qp], x[w+2Qp], x[w+3Qp] }, byte b = bits [8b+7:8b], so
 *    byte 0 is the least significant byte.
 *  - VROTB n: per-word rotate LEFT by n bits (n in {0, 8, 16, 24}).
 *  - A column buffer is [ W(0..Qp-1) | VROTB(W, 24) (Qp..2Qp-1) | padding ].
 *  - Each column is stored in the frame of the LAST layer that touches it;
 *    an edge rotates by delta = (s - s_prev) mod Z, s_prev being the shift
 *    of the previous layer touching that column (cyclically).
 *  - Qp must be a multiple of V (no tail-slice handling in this file).
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXZ 384
#define MAXC 68
#define MAXL 46
#define MAXD 24          /* max row degree */
#define MAXV 16          /* max vector length in 32-bit words */
#define MAXQ (MAXZ / 4)

#ifdef SCALE_ALT
#define SCALE34(m) ((m) - ((m) >> 2))
#else
#define SCALE34(m) ((3 * (m)) >> 2)
#endif

/*
 * Magnitude clamp applied to |Q| before the min search, so every message is
 * bounded by SCALE34(g_mag_max).  127 means "no clamp" (the original
 * behaviour).  A layered decoder with int8 posteriors needs this on real
 * codes: columns shared by dozens of layers keep L pinned at +-127 while the
 * stored messages R are as large as 95, so L - R_old can flip sign and the
 * decoder diverges after reaching the correct codeword.  Keeping |R| well
 * below the posterior range (about 1/4 of it) fixes that.  See ldpc_nr.c.
 */
static int g_mag_max = 127;

typedef int8_t llr_t;

typedef struct {
    int nb, mb, Z;
    int shift[MAXL][MAXC];       /* < 0: no edge */
} code_t;

static int sat8(int x) { return x > 127 ? 127 : (x < -127 ? -127 : x); }

/* ===================================================================== */
/*  1. Golden model: plain layered min-sum, canonical frame               */
/* ===================================================================== */

static llr_t Rref[MAXL][MAXC][MAXZ];

static void ref_decode(const code_t *K, llr_t (*L)[MAXZ], int iters)
{
    const int Z = K->Z;
    memset(Rref, 0, sizeof Rref);

    for (int it = 0; it < iters; it++) {
        for (int l = 0; l < K->mb; l++) {
            int ec[MAXD], es[MAXD], d = 0;
            for (int c = 0; c < K->nb; c++)
                if (K->shift[l][c] >= 0) { ec[d] = c; es[d] = K->shift[l][c]; d++; }
            assert(d >= 2 && d <= MAXD);

            int Q[MAXD][MAXZ], m1[MAXZ], m2[MAXZ], ix[MAXZ], sp[MAXZ];
            for (int i = 0; i < Z; i++) { m1[i] = m2[i] = 127; ix[i] = -1; sp[i] = 0; }

            for (int e = 0; e < d; e++) {              /* pass 1 */
                for (int i = 0; i < Z; i++) {
                    int q = sat8(L[ec[e]][(i + es[e]) % Z] - Rref[l][ec[e]][i]);
                    int m = q < 0 ? -q : q;
                    if (m > g_mag_max) m = g_mag_max;
                    Q[e][i] = q;
                    sp[i] ^= (q < 0);
                    if (m < m1[i])      { m2[i] = m1[i]; m1[i] = m; ix[i] = e; }
                    else if (m < m2[i]) { m2[i] = m; }
                }
            }
            for (int e = 0; e < d; e++) {              /* pass 2 */
                for (int i = 0; i < Z; i++) {
                    int mag = SCALE34(ix[i] == e ? m2[i] : m1[i]);
                    int neg = sp[i] ^ (Q[e][i] < 0);
                    int rn  = neg ? -mag : mag;
                    Rref[l][ec[e]][i] = (llr_t)rn;
                    L[ec[e]][(i + es[e]) % Z] = (llr_t)sat8(Q[e][i] + rn);
                }
            }
        }
    }
}

/* ===================================================================== */
/*  2. ISA-level primitives                                               */
/* ===================================================================== */

typedef uint32_t word_t;

static word_t rotl32(word_t w, unsigned n)
{
    n &= 31u;
    return n ? (w << n) | (w >> (32u - n)) : w;
}

static int lane_get(const word_t *v, int i)       /* signed byte lane i */
{
    int x = (int)((v[i >> 2] >> (8 * (i & 3))) & 0xFFu);
    return x >= 128 ? x - 256 : x;
}

static void lane_set(word_t *v, int i, int x)
{
    int sh = 8 * (i & 3);
    v[i >> 2] = (v[i >> 2] & ~(0xFFu << sh)) | ((word_t)(uint8_t)x << sh);
}

static void vld(word_t *d, const word_t *mem, int V)
{ for (int w = 0; w < V; w++) d[w] = mem[w]; }

static void vst(word_t *mem, const word_t *s, int V)
{ for (int w = 0; w < V; w++) mem[w] = s[w]; }

static void vrotb(word_t *d, const word_t *s, int V, unsigned bits)
{ for (int w = 0; w < V; w++) d[w] = rotl32(s[w], bits); }

static void vsubs8(word_t *d, const word_t *a, const word_t *b, int V)
{ for (int i = 0; i < 4 * V; i++) lane_set(d, i, sat8(lane_get(a, i) - lane_get(b, i))); }

static void vadds8(word_t *d, const word_t *a, const word_t *b, int V)
{ for (int i = 0; i < 4 * V; i++) lane_set(d, i, sat8(lane_get(a, i) + lane_get(b, i))); }

/* ---- AVU: internal check-node state, one set per byte lane ------------ */

typedef struct {
    int V;
    int min1[4 * MAXV], min2[4 * MAXV], idx[4 * MAXV], sp[4 * MAXV];
    int cmp_cnt;     /* edge number assigned by the next LCMP                */
    int msg_cnt;     /* edge number served by the next LMSG                  */
    int reading;     /* 0 until the first LMSG after the LCMPs               */
} avu_t;

static void lreset(avu_t *a, int V)
{
    a->V = V;
    for (int i = 0; i < 4 * V; i++) {
        a->min1[i] = a->min2[i] = 127; a->idx[i] = -1; a->sp[i] = 0;
    }
    a->cmp_cnt = a->msg_cnt = 0;
    a->reading = 0;
}

/* Digest one edge's Q vector: update min1/min2/index and sign parity. */
static void lcmp(avu_t *a, const word_t *q)
{
    for (int i = 0; i < 4 * a->V; i++) {
        int x = lane_get(q, i), m = x < 0 ? -x : x;
        if (m > g_mag_max) m = g_mag_max;
        a->sp[i] ^= (x < 0);
        if (m < a->min1[i])      { a->min2[i] = a->min1[i]; a->min1[i] = m; a->idx[i] = a->cmp_cnt; }
        else if (m < a->min2[i]) { a->min2[i] = m; }
    }
    a->cmp_cnt++;
    a->reading = 0;
}

/* Produce the next edge's new message (edges in the same order as LCMP).
 * q supplies the edge's own sign; if your AVU keeps per-edge signs
 * internally the operand is simply unused -- the result is identical.   */
static void lmsg(avu_t *a, word_t *out, const word_t *q)
{
    if (!a->reading) { a->msg_cnt = 0; a->reading = 1; }
    int e = a->msg_cnt++;
    for (int i = 0; i < 4 * a->V; i++) {
        int mag = SCALE34(a->idx[i] == e ? a->min2[i] : a->min1[i]);
        int neg = a->sp[i] ^ (lane_get(q, i) < 0);
        lane_set(out, i, neg ? -mag : mag);
    }
}

/* ===================================================================== */
/*  3. The kernel                                                         */
/* ===================================================================== */

typedef struct { int c, off, rot; } edge_t;       /* rot in bits */
typedef struct { int d; edge_t e[MAXD]; } layer_t;

static word_t colbuf[MAXC][2][2 * MAXQ + MAXV];   /* ping-pong, doubled */
static word_t Rmem[MAXL][MAXD][MAXQ];             /* uncompressed R messages */

static void build_edge_table(const code_t *K, layer_t *ly, int *fend)
{
    const int Z = K->Z, Qp = Z / 4;
    int prev[MAXC];

    for (int c = 0; c < K->nb; c++) {             /* frame of last touch */
        fend[c] = 0;
        for (int l = 0; l < K->mb; l++)
            if (K->shift[l][c] >= 0) fend[c] = K->shift[l][c];
        prev[c] = fend[c];
    }
    for (int l = 0; l < K->mb; l++) {
        ly[l].d = 0;
        for (int c = 0; c < K->nb; c++) {
            int s = K->shift[l][c];
            if (s < 0) continue;
            int delta = ((s - prev[c]) % Z + Z) % Z;
            int rho   = (Z - delta) % Z;
            int u = rho / Qp, t = rho % Qp;
            edge_t *E = &ly[l].e[ly[l].d++];
            E->c = c; E->off = Qp - t; E->rot = 8 * ((u + 1) % 4);
            prev[c] = s;
        }
        assert(ly[l].d >= 2 && ly[l].d <= MAXD);
    }
}

static void dump_edge_table(const code_t *K, const layer_t *ly, const int *fend)
{
    printf("Qp = %d words per column; columns stored in frame:", K->Z / 4);
    for (int c = 0; c < K->nb; c++) printf(" c%d:%d", c, fend[c]);
    printf("\n");
    for (int l = 0; l < K->mb; l++)
        for (int e = 0; e < ly[l].d; e++)
            printf("  layer %d edge %d: col %d shift %d  word_off %d  rot_bits %d\n",
                   l, e, ly[l].e[e].c, K->shift[l][ly[l].e[e].c],
                   ly[l].e[e].off, ly[l].e[e].rot);
}

/* L is in/out, canonical frame. Returns 0, or -1 if Z/V is unsupported. */
static int kern_decode(const code_t *K, int V, llr_t (*L)[MAXZ], int iters, int dump)
{
    const int Z = K->Z, Qp = Z / 4;
    if (Z % 4 || V < 1 || V > MAXV || Qp % V) return -1;
    const int NV = Qp / V;

    layer_t ly[MAXL];
    int fend[MAXC], cur[MAXC];
    build_edge_table(K, ly, fend);
    if (dump) dump_edge_table(K, ly, fend);

    memset(colbuf, 0, sizeof colbuf);
    memset(Rmem, 0, sizeof Rmem);

    /* pre-rotate channel LLRs into each column's end-of-iteration frame, pack */
    for (int c = 0; c < K->nb; c++) {
        cur[c] = 0;
        for (int w = 0; w < Qp; w++) {
            word_t word = 0;
            for (int b = 0; b < 4; b++) {
                int x = L[c][(w + b * Qp + fend[c]) % Z];
                word |= (word_t)(uint8_t)x << (8 * b);
            }
            colbuf[c][0][w]      = word;
            colbuf[c][0][Qp + w] = rotl32(word, 24);
        }
    }

    avu_t avu;
    word_t vQ[MAXD][MAXV], vL[MAXV], vR[MAXV], vN[MAXV];

    for (int it = 0; it < iters; it++) {
        for (int l = 0; l < K->mb; l++) {
            const layer_t *Ly = &ly[l];
            for (int v = 0; v < NV; v++) {
                lreset(&avu, V);
                for (int e = 0; e < Ly->d; e++) {                 /* pass 1 */
                    const edge_t *E = &Ly->e[e];
                    vld(vL, colbuf[E->c][cur[E->c]] + E->off + v * V, V);
                    vrotb(vL, vL, V, (unsigned)E->rot);
                    vld(vR, &Rmem[l][e][v * V], V);
                    vsubs8(vQ[e], vL, vR, V);
                    lcmp(&avu, vQ[e]);
                }
                for (int e = 0; e < Ly->d; e++) {                 /* pass 2 */
                    const edge_t *E = &Ly->e[e];
                    word_t *dst = colbuf[E->c][1 - cur[E->c]];
                    lmsg(&avu, vN, vQ[e]);
                    vst(&Rmem[l][e][v * V], vN, V);
                    vadds8(vL, vQ[e], vN, V);
                    vst(dst + v * V, vL, V);
                    vrotb(vL, vL, V, 24);
                    vst(dst + Qp + v * V, vL, V);
                }
            }
            for (int e = 0; e < Ly->d; e++) cur[Ly->e[e].c] ^= 1; /* swap */
            /* DRAIN (store fence) goes here on the machine */
        }
    }

    /* unpack, undo the end-of-iteration frame */
    for (int c = 0; c < K->nb; c++)
        for (int w = 0; w < Qp; w++)
            for (int b = 0; b < 4; b++) {
                int x = lane_get(&colbuf[c][cur[c]][w], b);
                L[c][(w + b * Qp + fend[c]) % Z] = (llr_t)x;
            }
    return 0;
}

/* ===================================================================== */
/*  4. Test harness                                                       */
/* ===================================================================== */

static uint32_t rng_state = 20261008u;
static uint32_t rnd(void)
{ uint32_t x = rng_state; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return rng_state = x; }
static int rndr(int lo, int hi) { return lo + (int)(rnd() % (uint32_t)(hi - lo + 1)); }

static code_t code_new(int nb, int mb, int Z)
{
    code_t k; memset(&k, 0, sizeof k);
    k.nb = nb; k.mb = mb; k.Z = Z;
    for (int l = 0; l < MAXL; l++) for (int c = 0; c < MAXC; c++) k.shift[l][c] = -1;
    return k;
}

static int syndrome_ok(const code_t *K, llr_t (*L)[MAXZ])
{
    for (int l = 0; l < K->mb; l++)
        for (int i = 0; i < K->Z; i++) {
            int p = 0;
            for (int c = 0; c < K->nb; c++)
                if (K->shift[l][c] >= 0) p ^= (L[c][(i + K->shift[l][c]) % K->Z] < 0);
            if (p) return 0;
        }
    return 1;
}

static int frames_equal(const code_t *K, llr_t (*A)[MAXZ], llr_t (*B)[MAXZ])
{
    for (int c = 0; c < K->nb; c++)
        if (memcmp(A[c], B[c], (size_t)K->Z)) return 0;
    return 1;
}

static llr_t FA[MAXC][MAXZ], FB[MAXC][MAXZ];

/* toy code from the worked example: Z = 4, 2 layers, one flipped bit */
static int toy_test(int dump)
{
    code_t K = code_new(4, 2, 4);
    K.shift[0][0] = 1; K.shift[0][1] = 0; K.shift[0][2] = 2;
    K.shift[1][1] = 3; K.shift[1][2] = 1; K.shift[1][3] = 0;
    const llr_t in[4][4] = { { 9, 7, 8, 6 }, { 8, -4, 9, 7 }, { 7, 9, 6, 8 }, { 6, 8, 7, 9 } };
    for (int c = 0; c < 4; c++) for (int i = 0; i < 4; i++) FA[c][i] = FB[c][i] = in[c][i];

    ref_decode(&K, FA, 1);
    if (kern_decode(&K, 1, FB, 1, dump)) { printf("toy: unsupported config\n"); return 1; }
    int same = frames_equal(&K, FA, FB);
    printf("toy code, 1 iteration: kernel %s reference, syndrome %s\n",
           same ? "==" : "!=", syndrome_ok(&K, FB) ? "OK (decoded)" : "FAILED");
    printf("  column 1 LLRs after decode: %d %d %d %d (bit 5 was -4)\n",
           FB[1][0], FB[1][1], FB[1][2], FB[1][3]);
    return !same;
}

static int random_tests(void)
{
    static const struct { int Z, V; } cfg[] = {
        { 4, 1 }, { 8, 2 }, { 32, 4 }, { 32, 8 }, { 64, 4 }, { 64, 16 },
        { 96, 8 }, { 96, 4 }, { 128, 8 }, { 128, 16 }, { 240, 5 }, { 384, 16 }, { 384, 8 },
    };
    int trials = 0, bad = 0, converged = 0;

    for (unsigned k = 0; k < sizeof cfg / sizeof cfg[0]; k++) {
        for (int rep = 0; rep < 12; rep++) {
            int Z = cfg[k].Z, V = cfg[k].V;
            int nb = rndr(7, 12), mb = rndr(3, 6);
            code_t K = code_new(nb, mb, Z);
            for (int l = 0; l < mb; l++) {
                int deg = rndr(3, nb < 6 ? nb : 6), pick[MAXC];
                for (int c = 0; c < nb; c++) pick[c] = c;
                for (int j = 0; j < deg; j++) {            /* partial shuffle */
                    int r = rndr(j, nb - 1), t = pick[j]; pick[j] = pick[r]; pick[r] = t;
                    K.shift[l][pick[j]] = rndr(0, Z - 1);
                }
            }
            int mode = rep % 3;
            for (int c = 0; c < nb; c++)
                for (int i = 0; i < Z; i++) {
                    int x;
                    if (mode == 0)      x = rndr(-20, 20);
                    else if (mode == 1) x = rndr(-127, 127);          /* exercise saturation */
                    else { x = rndr(10, 100); if (rnd() % 10 == 0) x = -x; }
                    FA[c][i] = FB[c][i] = (llr_t)x;
                }
            int iters = rndr(1, 6);
            ref_decode(&K, FA, iters);
            if (kern_decode(&K, V, FB, iters, 0)) continue;       /* unsupported combo */
            trials++;
            if (!frames_equal(&K, FA, FB)) {
                bad++;
                printf("MISMATCH Z=%d V=%d nb=%d mb=%d iters=%d mode=%d\n", Z, V, nb, mb, iters, mode);
            }
            converged += syndrome_ok(&K, FA);
        }
    }
    printf("random codes: %d trials, %d mismatches (%d of them reached a valid codeword)\n",
           trials, bad, converged);
    return bad;
}

int main(int argc, char **argv)
{
    int dump = argc > 1 && !strcmp(argv[1], "-d");
    int bad = toy_test(dump);
    bad += random_tests();
    printf(bad ? "FAIL\n" : "PASS\n");
    return bad != 0;
}
