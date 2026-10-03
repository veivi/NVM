	.export "fft_dit_radix4"
	.import "w_table"

#include <VU102.h>
#include <common.h>

	.section "code"

#if V == 4
#define LOG4V  1
#elif V == 16
#define LOG4V  2
#endif
	
fft_dit_radix4:
	debug 48
	
	// Params: s1 = data, s2 = log4(N)

#define reg_A          s1
#define reg_LOG4N      s2
	
	// Full outer loop is
	//   for stage = 1 .. log4(N):
	//
	// Early stage condition:
	//   quarter < V
	//   <==> span / 4 < V
	//   <==> span < 4*V
	//   <==> 4^s < 4*V
	//   <==> s < LOG4(4*V)
	//   <==> s < 1 + LOG4(V)
	//
  
	// for(s = 1; s <= LOG4V; s++) {
	//    span = 1<<(2 * s);  // 4^s
	//    quarter = span / 4;
	//    index_mult = FFT_LEN / span;
	
#define reg_s           s3
#define reg_span        s4
#define reg_quarter     s5
#define reg_index_mult  s6
#define reg_w_table     s7
#define reg_fft_len     s8	
	
	ldi reg_s, 1               // s = 1
	ldi reg_w_table, w_table
	lsl reg_fft_len, reg_LOG4N, 1
	lsl reg_fft_len, reg_s, reg_fft_len // fft_len = 1<<(2*log4(N))

for_s_loop_early:
	lsl reg_span, reg_s, 1          // span = 2*s
	ldi reg_quarter, 1
	lsl reg_span, reg_quarter, reg_span   // span = 1<<(2*s) = 4^s
	lsr reg_quarter, reg_span, 2    // quarter = span/4
	lsl reg_index_mult, reg_s, 1    // index_mult = 2*s
	lsr reg_index_mult, reg_fft_len, reg_index_mult  // index_mult = FFT_LEN/4^s = FFT_LEN/span
	
	// early stage: small blocks, broadcast twiddle, strided across blocks
	// for j = 0 .. quarter-1:
	//
	// for(j = 0; j < quarter; j++) {

#define reg_j          s9

	clear(reg_j)

for_j_loop_early:
	
	// Pseudo: w1j, w2j, w3j = twid1[j], twid2[j], twid3[j]   // scalars
	//
	// C: complex_t w1j = w[j * index_mult], w2j = w[j * 2*index_mult], w3j = w[j * 3*index_mult];
	//    int kb = 0;

#define reg_w1j       s10
#define reg_w2j       s10
#define reg_w3j       s10
#define reg_delta     s11
#define reg_temp      s12	

	// j * index_mult = j * FFT_LEN/4^s = j<<(2*log4(N))>>(2*s) = j<<(2*(log4(N) - s))

	sub reg_delta, s2, reg_s         // delta = log4(N) - s
	lsl reg_delta, reg_delta, 1      // delta = 2*(log4(N) - s)
	lsl reg_delta, reg_j, reg_delta  // delta = j<<(2*(log4(N) - s)) = j * index_mult

	ldx reg_w1j, reg_w_table, reg_delta  // w1j = w_table[j * mult]
	lsl reg_temp, reg_delta, 1           // temp = 2 * j * mult
	ldx reg_w2j, reg_w_table, reg_temp   // w2j = w_table[2 * j * mult]
	add reg_temp, reg_temp, reg_delta    // temp = 3 * j * mul
	ldx reg_w3j, reg_w_table, reg_temp   // w3j = w_table[3 * j * mult]

	// for(kb = 0; kb < FFT_LEN; kb += V*span) {
	//      printf("---\ns = %d j = %d, kb = %d\n---\n", s, j, kb);
	
#define reg_kb        s13	
#define reg_4kbj      s14	
#define reg_V_x_span  s15	
#define reg_a0        v0
#define reg_a1        v1
#define reg_a2        v2
#define reg_a3        v3
#define reg_t0        v4
#define reg_t1        v5
#define reg_t2        v6
#define reg_t3        v7
#define reg_s0        v8
#define reg_s1        v9
#define reg_s2        v10
#define reg_s3        v11
#define reg_y0        v12
#define reg_y1        v13
#define reg_y2        v14
#define reg_y3        v15
#define reg_r3        v16
#define reg_w1        v17
#define reg_w2        v18
#define reg_w3        v19
	
	clear(reg_kb)
	lsl reg_V_x_span, reg_span, LOG2V  // Vspan = span<<LOG2V = V * span

for_kb_loop:
#ifdef DEBUG
	lsl s50, reg_s, 16
	or s50, s50, reg_j
	debugr s50
	debug 0
	debugr reg_kb
#endif
	/* 
	    VLD    a0, [a + kb + j],            stride=span
	    VLD    a1, [a + kb + j + quarter],    stride=span
	    VLD    a2, [a + kb + j + 2*quarter],  stride=span
	    VLD    a3, [a + kb + j + 3*quarter],  stride=span

	  complex_vector_read(a0, A, kb + j, span, 0x130);
	  complex_vector_read(a1, A, kb + j + quarter, span, 0x130);
	  complex_vector_read(a2, A, kb + j + 2*quarter, span, 0x130);
	  complex_vector_read(a3, A, kb + j + 3*quarter, span, 0x130);
	*/

	add reg_4kbj, reg_kb, reg_j    // 4kbj = kb + j
	lsl reg_4kbj, reg_4kbj, 2      // 4kbj = 4*(kb + j)
	add reg_temp, reg_A, reg_4kbj  // temp = &A[kb + j]
	vld reg_a0, reg_temp, reg_span // complex_vector_read(a0, A, kb + j, span)

	lsl reg_delta, reg_quarter, 2     // delta = 4 * quarter
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + quarter]
	vld reg_a1, reg_temp, reg_span    // complex_vector_read(a1, A, kb + j + quarter, span)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + 2*quarter]
	vld reg_a2, reg_temp, reg_span    // complex_vector_read(a2, A, kb + j + 2*quarter, span)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + 3*quarter]
	vld reg_a3, reg_temp, reg_span    // complex_vector_read(a3, A, kb + j + 3*quarter, span)
	
	/*
            t0 = a0
            VBCMUL t1, w1j, a1
            VBCMUL t2, w2j, a2
            VBCMUL t3, w3j, a3
	
	  complex_vector_mul_bc(t1, a1, &w1j);
	  complex_vector_mul_bc(t2, a2, &w2j);
	  complex_vector_mul_bc(t3, a3, &w3j);
	*/

	cvbmul reg_t1, reg_a1, reg_w1j
	cvbmul reg_t2, reg_a2, reg_w2j
	cvbmul reg_t3, reg_a3, reg_w3j

	/*
            VCADD s0, t0, t2    VCSUB s1, t0, t2
            VCADD s2, t1, t3    VCSUB s3, t1, t3

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);
	*/

	cvadd reg_s0, reg_a0, reg_t2
	cvsub reg_s1, reg_a0, reg_t2
	cvadd reg_s2, reg_t1, reg_t3
	cvsub reg_s3, reg_t1, reg_t3

	/*
            VCADD y0, s0, s2
            VCSUB y2, s0, s2
            VROTNJ r3n, s3      VROTJ r3p, s3
            VCADD y1, s1, r3n
            VCADD y3, s1, r3p

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);
	*/

	cvadd reg_y0, reg_s0, reg_s2
	cvsub reg_y2, reg_s0, reg_s2
	vrotc reg_r3, reg_s3, -1
	cvadd reg_y1, reg_s1, reg_r3
	vrotc reg_r3, reg_s3, 1
	cvadd reg_y3, reg_s1, reg_r3

	/*
            VST [a + kb + j],            y0, stride=span
            VST [a + kb + j + quarter],    y1, stride=span
            VST [a + kb + j + 2*quarter],  y2, stride=span
            VST [a + kb + j + 3*quarter],  y3, stride=span

	  complex_vector_write(y0, A, kb + j, span, 0x130);
	  complex_vector_write(y1, A, kb + j + quarter, span, 0x130);
	  complex_vector_write(y2, A, kb + j + 2*quarter, span, 0x130);
	  complex_vector_write(y3, A, kb + j + 3*quarter, span, 0x130);
	*/

	add reg_temp, reg_A, reg_4kbj  // temp = &A[kb + j]
	vst reg_y0, reg_temp, reg_span // complex_vector_write(y0, A, kb + j + quarter, span)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + quarter]
	vst reg_y1, reg_temp, reg_span    // complex_vector_write(y1, A, kb + j + quarter, span)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + 2*quarter]
	vst reg_y2, reg_temp, reg_span    // complex_vector_write(y2, A, kb + j + 2*quarter, span)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[kb + j + 3*quarter]

	// end for(kb = 0; kb < FFT_LEN; kb += V*span)
	
	add reg_kb, reg_kb, reg_V_x_span     // kb += V * span
	cmp c0, reg_kb, reg_fft_len       // c0 = compare(kb, fft_len)

	blt c0, for_kb_loop               // while kb < fft_len
	vst reg_y3, reg_temp, reg_span    // complex_vector_write(y3, A, kb + j + 3*quarter, span)

	//
	// end for(j = 0; j < quarter; j++)
	//

	add reg_j, reg_j, 1
	cmp c0, reg_j, reg_quarter
	blt c0, for_j_loop_early
	nop

	//
	// end for(s = 1; s <= LOG4V; s++)
	//

	add reg_s, reg_s, 1
	cmp c0, reg_s, LOG4V
	ble c0, for_s_loop_early
	nop
	
	// for(s = LOG4V + 1; s <= log4(N); s++) {

for_s_loop_late:	
	// late stage: contiguous within a block, twiddle vectors
	//
	// span    = 4^stage
	// quarter = span / 4

	lsl reg_span, reg_s, 1          // span = 2*s
	ldi reg_quarter, 1
	lsl reg_span, reg_quarter, reg_span   // span = 1<<(2*s) = 4^s
	lsr reg_quarter, reg_span, 2    // quarter = span/4
	lsl reg_index_mult, reg_s, 1    // index_mult = 2*s
	lsr reg_index_mult, reg_fft_len, reg_index_mult  // index_mult = FFT_LEN/4^s = FFT_LEN/span
		
#define reg_k              s13
#define reg_4kj            s14
#define reg_delta_j        s16
#define reg_delta_delta_j  s17
#define reg_w_stride       s18
	
	// Pseudo: for j = 0, V, 2V, ... quarter-V:
	//
	// for(j = 0; j < quarter; j += V) {

	clear(reg_j)

	//
	// delta_j = j * index_mult = j * fft_len>>(2*s)
	// Because j increments by V:
	// delta_delta_j = V * fft_len>>(2**s)
	//   = (1<<LOG2V) * fft_len>>(2*s)
	//   = (1<<LOG2V) * ((1<<(2*log4(N)))>>(2*s))
	//   = (1<<LOG2V) * (1<<(2*(log4(N) - s)))
	//   = 1<<(LOG2V + 2*(log4(N) - s))
	//

	sub reg_delta_delta_j, reg_LOG4N, reg_s
	lsl reg_delta_delta_j, reg_delta_delta_j, 1
	add reg_delta_delta_j, reg_delta_delta_j, LOG2V
	ldi reg_temp, 1
	lsl reg_delta_delta_j, reg_temp, reg_delta_delta_j

	clear(reg_delta_j)

for_j_loop_late:
	
	/*
          VLD   w1, [twid1 + j]
          VLD   w2, [twid2 + j]
          VLD   w3, [twid3 + j]
	  
	  complex_vector_read(w1, w, j * index_mult, index_mult, 0x10000);
	  complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult, 0x10000);
	  complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult, 0x10000);
	*/

	add reg_temp, reg_w_table, reg_delta_j
	move(reg_w_stride, reg_index_mult)
	vld reg_w1, reg_temp, reg_w_stride // complex_vector_read(w1, w, j * index_mult, index_mult)

	add reg_temp, reg_temp, reg_delta_j
	add reg_w_stride, reg_w_stride, reg_index_mult
	vld reg_w2, reg_temp, reg_w_stride // complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult)
	
	add reg_temp, reg_temp, reg_delta_j
	add reg_w_stride, reg_w_stride, reg_index_mult
	vld reg_w3, reg_temp, reg_w_stride // complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult)

	//
	// Pseudo: for k = 0, span, 2*span, ... N-span:
	//
	// for(k = 0; k < FFT_LEN; k += span)
	//

	clear(reg_k)

for_k_loop_late:	
#ifdef DEBUG
	lsl s50, reg_s, 16
	or s50, s50, reg_j
	debugr s50
	debug 0xFFFF
	debugr reg_kb
#endif
	/*
                VLD   a0, [a + k+j]
                VLD   a1, [a + k+j+quarter]
                VLD   a2, [a + k+j+2*quarter]
                VLD   a3, [a + k+j+3*quarter]

	  complex_vector_read(a0, A, k + j, 1, 0x130);
	  complex_vector_read(a1, A, k + j + quarter, 1, 0x130);
	  complex_vector_read(a2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_read(a3, A, k + j + 3*quarter, 1, 0x130);
	*/

	add reg_4kj, reg_k, reg_j    // 4kj = k + j
	lsl reg_4kj, reg_4kj, 2      // 4kj = 4*(k + j)
	
	add reg_temp, reg_A, reg_4kj  // temp = &A[k + j]
	vld reg_a0, reg_temp, 1 // complex_vector_read(a0, A, k + j, 1)

	lsl reg_delta, reg_quarter, 2     // delta = 4 * quarter
	add reg_temp, reg_temp, reg_delta // temp = &A[k + j + quarter]
	vld reg_a1, reg_temp, 1 // complex_vector_read(a1, A, k + j + quarter, 1)

	add reg_temp, reg_temp, reg_delta // temp = &A[k + j + 2*quarter]
	vld reg_a2, reg_temp, 1 // complex_vector_read(a2, A, k + j + 2*quarter, 1)
	
	add reg_temp, reg_temp, reg_delta // temp = &A[k + j + 3*quarter]
	vld reg_a3, reg_temp, 1 // complex_vector_read(a3, A, k + j + 3*quarter, 1)

	/*
                t0 = a0
                VCMUL t1, w1, a1
                VCMUL t2, w2, a2
                VCMUL t3, w3, a3

	complex_vector_mul(t1, w1, a1);
	complex_vector_mul(t2, w2, a2);
	complex_vector_mul(t3, w3, a3);

	*/

	cvmul reg_t1, reg_w1, reg_a1
	cvmul reg_t2, reg_w2, reg_a2
	cvmul reg_t3, reg_w3, reg_a3
	
	/*
                VCADD s0, t0, t2    VCSUB s1, t0, t2
                VCADD s2, t1, t3    VCSUB s3, t1, t3

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);
	*/

	cvadd reg_s0, reg_a0, reg_t2
	cvsub reg_s1, reg_a0, reg_t2
	cvadd reg_s2, reg_t1, reg_t3
	cvsub reg_s3, reg_t1, reg_t3
	
	/*
                VCADD y0, s0, s2
                VCSUB y2, s0, s2
                VROTNJ r3n, s3      VROTJ r3p, s3
                VCADD y1, s1, r3n
                VCADD y3, s1, r3p

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);
	*/

	cvadd reg_y0, reg_s0, reg_s2
	cvsub reg_y2, reg_s0, reg_s2
	vrotc reg_r3, reg_s3, -1
	cvadd reg_y1, reg_s1, reg_r3
	vrotc reg_r3, reg_s3, 1
	cvsub reg_y3, reg_s1, reg_r3
	
	/*
                VST [a + k+j],           y0
                VST [a + k+j+quarter],   y1
                VST [a + k+j+2*quarter], y2
                VST [a + k+j+3*quarter], y3

	  complex_vector_write(y0, A, k + j, 1, 0x130);
	  complex_vector_write(y1, A, k + j + quarter, 1, 0x130);
	  complex_vector_write(y2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_write(y3, A, k + j + 3*quarter, 1, 0x130);
	*/

	add reg_temp, reg_A, reg_4kj
	vst reg_y0, reg_temp, 1
	
	add reg_temp, reg_temp, reg_delta
	vst reg_y1, reg_temp, 1
	
	add reg_temp, reg_temp, reg_delta
	vst reg_y2, reg_temp, 1
	
	add reg_temp, reg_temp, reg_delta

	// end for(k = 0; k < FFT_LEN; k += span)

	add reg_k, reg_k, reg_span
	cmp c0, reg_k, reg_fft_len
	blt c0, for_k_loop_late
	vst reg_y3, reg_temp, 1
	
	// end for(j = 0; j < quarter; j += V) {

	add reg_j, reg_j, V
	cmp c0, reg_j, reg_quarter
	blt c0, for_j_loop_late
	add reg_delta_j, reg_delta_j, reg_delta_delta_j

	// end for(s = LOG4V + 1; s <= log4(N); s++) {

	add reg_s, reg_s, 1
	cmp c0, reg_s, reg_LOG4N
	ble c0, for_s_loop_late
	drain      // Store fence

	// Done

	ret
	nop
