///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
// 
// PROPRIETARY AND CONFIDENTIAL.
// Unauthorized copying, modification, or distribution of this file, 
// via any medium, is strictly prohibited.
//
///////////////////////////////////////////////////////////////////////////////

	.export "fft_dit_radix4_unroll4"
	.import "w_table"

#include <VU102.h>
#include <common.h>

	.section "code"

#if EFF_V == 16
#define EFF_LOG4V  2
#elif EFF_V == 64
#define EFF_LOG4V  3
#endif

#ifdef EFF_LOG4V
fft_dit_radix4_unroll4:
	debug 48

	prologue(s3)
	
	// Params: s1 = data, s2 = log4(N)

#define S_A          s1
#define S_LOG4N      s2
	
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
  
	// for(s = 1; s <= EFF_LOG4V; s++) {
	//    span = 1<<(2 * s);  // 4^s
	//    quarter = span / 4;
 	//    index_mult = FFT_LEN / span;
	
#define S_s           s3
#define S_span        s4
#define S_quarter     s5
#define S_index_mult  s6
#define S_W           s7
#define S_fft_len     s8	
	
	ldi S_s, 1               // s = 1
	load_big(S_W, w_table)
	lsl S_fft_len, S_LOG4N, 1
	lsl S_fft_len, S_s, S_fft_len // fft_len = 1<<(2*log4(N))

for_s_loop_early:
	lsl S_span, S_s, 1          // span = 2*s
	ldi S_quarter, 1
	lsl S_span, S_quarter, S_span   // span = 1<<(2*s) = 4^s
	lsr S_quarter, S_span, 2    // quarter = span/4
	lsl S_index_mult, S_s, 1    // index_mult = 2*s
	lsr S_index_mult, S_fft_len, S_index_mult  // index_mult = FFT_LEN/4^s = FFT_LEN/span
	
	// early stage: small blocks, broadcast twiddle, strided across blocks
	// for j = 0 .. quarter-1:
	//
	// for(j = 0; j < quarter; j++) {

#define S_j          s9

	clear(S_j)

for_j_loop_early:
	
	// Pseudo: w1j, w2j, w3j = twid1[j], twid2[j], twid3[j]   // scalars
	//
	// C: complex_t w1j = w[j * index_mult], w2j = w[j * 2*index_mult], w3j = w[j * 3*index_mult];
	//    int kb = 0;

#define S_w1j       s10
#define S_w2j       s11
#define S_w3j       s12
#define S_delta     s13
#define S_2_x_delta    s14
#define S_temp      s15	

	// j * index_mult = j * FFT_LEN/4^s = j<<(2*log4(N))>>(2*s) = j<<(2*(log4(N) - s))

	sub S_delta, s2, S_s         // delta = log4(N) - s
	lsl S_delta, S_delta, 1      // delta = 2*(log4(N) - s)
	lsl S_delta, S_j, S_delta  // delta = j<<(2*(log4(N) - s)) = j * index_mult

	ldx S_w1j, S_W, S_delta  // w1j = W[j * mult]
	lsl S_temp, S_delta, 1           // temp = 2 * j * mult
	ldx S_w2j, S_W, S_temp   // w2j = W[2 * j * mult]
	add S_temp, S_temp, S_delta    // temp = 3 * j * mul
	ldx S_w3j, S_W, S_temp   // w3j = W[3 * j * mult]

	lsl S_delta, S_quarter, 2     // delta = 4 * quarter
	lsl S_2_x_delta, S_delta, 1      // 2_x_delta = 8 * quarter
	
	// for(kb = 0; kb < FFT_LEN; kb += V*span) {
	//      printf("---\ns = %d j = %d, kb = %d\n---\n", s, j, kb);
	
#define S_kb        s16	
#define S_4kbj      s17	
#define S_V_x_span  s18	
#define V_w1        v0
#define V_w1_2      v1
#define V_w1_3      v2
#define V_w1_4      v3
#define V_w2        v4
#define V_w2_2      v5
#define V_w2_3      v6
#define V_w2_4      v7
#define V_w3        v8
#define V_w3_2      v9
#define V_w3_3      v10
#define V_w3_4      v11
#define V_a0        v16
#define V_a0_2      v17
#define V_a0_3      v18
#define V_a0_4      v19
#define V_a1        v20
#define V_a1_2      v21
#define V_a1_3      v22
#define V_a1_4      v23
#define V_a2        v24
#define V_a2_2      v25
#define V_a2_3      v26
#define V_a2_4      v27
#define V_a3        v28
#define V_a3_2      v29
#define V_a3_3      v30
#define V_a3_4      v31
#define V_t0        v32
#define V_t0_2      v33
#define V_t0_3      v34
#define V_t0_4      v35
#define V_t1        v36
#define V_t1_2      v37
#define V_t1_3      v38
#define V_t1_4      v39
#define V_t2        v40
#define V_t2_2      v41
#define V_t2_3      v42
#define V_t2_4      v43
#define V_t3        v44
#define V_t3_2      v45
#define V_t3_3      v46
#define V_t3_4      v47
#define V_s0        v48
#define V_s0_2      v49
#define V_s0_3      v50
#define V_s0_4      v51
#define V_s1        v52
#define V_s1_2      v53
#define V_s1_3      v54
#define V_s1_4      v55
#define V_s2        v56
#define V_s2_2      v57
#define V_s2_3      v58
#define V_s2_4      v59
#define V_s3        v60
#define V_s3_2      v61
#define V_s3_3      v62
#define V_s3_4      v63
#define V_y0        v16
#define V_y0_2      v17
#define V_y0_3      v18
#define V_y0_4      v19
#define V_y1        v20
#define V_y1_2      v21
#define V_y1_3      v22
#define V_y1_4      v23
#define V_y2        v24
#define V_y2_2      v25
#define V_y2_3      v26
#define V_y2_4      v27
#define V_y3        v28
#define V_y3_2      v29
#define V_y3_3      v30
#define V_y3_4      v31
	
	clear(S_kb)
	lsl S_V_x_span, S_span, EFF_LOG2V  // Vspan = span<<LOG2V = V * span

for_kb_loop:
#ifdef DEBUG
	debug 0xB00B
	lsl s50, S_s, 16
	or s50, s50, S_j
	debugr s50
	debugr S_kb
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

	add S_4kbj, S_kb, S_j    // 4kbj = kb + j
	lsl S_4kbj, S_4kbj, 2      // 4kbj = 4*(kb + j)
	add S_temp, S_A, S_4kbj  // temp = &A[kb + j]
	add S_temp, S_temp, S_delta // temp = &A[kb + j + quarter]
	vld.4 V_a1, S_temp, S_span    // complex_vector_read(a1, A, kb + j + quarter, span)
	
	add S_temp, S_temp, S_delta // temp = &A[kb + j + 2*quarter]
	vld.4 V_a2, S_temp, S_span    // complex_vector_read(a2, A, kb + j + 2*quarter, span)
	
	add S_temp, S_temp, S_delta // temp = &A[kb + j + 3*quarter]
	vld.4 V_a3, S_temp, S_span    // complex_vector_read(a3, A, kb + j + 3*quarter, span)

	add S_temp, S_A, S_4kbj  // temp = &A[kb + j]
	vld.4 V_a0, S_temp, S_span // complex_vector_read(a0, A, kb + j, span)
		
	/*
            t0 = a0
            VBCMUL t1, w1j, a1
            VBCMUL t2, w2j, a2
            VBCMUL t3, w3j, a3
	
	  complex_vector_mul_bc(t1, a1, &w1j);
	  complex_vector_mul_bc(t2, a2, &w2j);
	  complex_vector_mul_bc(t3, a3, &w3j);
	*/

	cvbmul V_t1, V_a1, S_w1j
	cvbmul V_t1_2, V_a1_2, S_w1j
	cvbmul V_t1_3, V_a1_3, S_w1j
	cvbmul V_t1_4, V_a1_4, S_w1j
	cvbmul V_t2, V_a2, S_w2j
	cvbmul V_t2_2, V_a2_2, S_w2j
	cvbmul V_t2_3, V_a2_3, S_w2j
	cvbmul V_t2_4, V_a2_4, S_w2j
	cvbmul V_t3, V_a3, S_w3j
	cvbmul V_t3_2, V_a3_2, S_w3j
	cvbmul V_t3_3, V_a3_3, S_w3j
	cvbmul V_t3_4, V_a3_4, S_w3j

	/*
            VCADD s0, t0, t2    VCSUB s1, t0, t2
            VCADD s2, t1, t3    VCSUB s3, t1, t3

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);
	*/

	cvadd V_s0, V_a0, V_t2
	cvadd V_s0_2, V_a0_2, V_t2_2
	cvadd V_s0_3, V_a0_3, V_t2_3
	cvadd V_s0_4, V_a0_4, V_t2_4
	cvsub V_s1, V_a0, V_t2
	cvsub V_s1_2, V_a0_2, V_t2_2
	cvsub V_s1_3, V_a0_3, V_t2_3
	cvsub V_s1_4, V_a0_4, V_t2_4
	cvadd V_s2, V_t1, V_t3
	cvadd V_s2_2, V_t1_2, V_t3_2
	cvadd V_s2_3, V_t1_3, V_t3_3
	cvadd V_s2_4, V_t1_4, V_t3_4
	cvsub V_s3, V_t1, V_t3
	cvsub V_s3_2, V_t1_2, V_t3_2
	cvsub V_s3_3, V_t1_3, V_t3_3
	cvsub V_s3_4, V_t1_4, V_t3_4

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

	cvadd V_y0, V_s0, V_s2
	cvadd V_y0_2, V_s0_2, V_s2_2
	cvadd V_y0_3, V_s0_3, V_s2_3
	cvadd V_y0_4, V_s0_4, V_s2_4

	cvsub V_y2, V_s0, V_s2
	cvsub V_y2_2, V_s0_2, V_s2_2
	cvsub V_y2_3, V_s0_3, V_s2_3
	cvsub V_y2_4, V_s0_4, V_s2_4
	
	add S_temp, S_A, S_4kbj  // temp = &A[kb + j]
	vst.4 V_y0, S_temp, S_span // complex_vector_write(y0, A, kb + j, span)
	
	cvaddrni V_y1, V_s1, V_s3
	cvaddrni V_y1_2, V_s1_2, V_s3_2
	cvaddrni V_y1_3, V_s1_3, V_s3_3
	cvaddrni V_y1_4, V_s1_4, V_s3_4
	
	add S_temp, S_temp, S_2_x_delta // temp = &A[kb + j + 2*quarter]
	vst.4 V_y2, S_temp, S_span    // complex_vector_write(y2, A, kb + j + 2*quarter, span)
	
	cvaddri V_y3, V_s1, V_s3
	cvaddri V_y3_2, V_s1_2, V_s3_2
	cvaddri V_y3_3, V_s1_3, V_s3_3
	cvaddri V_y3_4, V_s1_4, V_s3_4

	sub S_temp, S_temp, S_delta // temp = &A[kb + j + quarter]
	vst.4 V_y1, S_temp, S_span    // complex_vector_write(y1, A, kb + j + quarter, span)
	
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

	add S_temp, S_temp, S_2_x_delta // temp = &A[kb + j + 3*quarter]

	// end for(kb = 0; kb < FFT_LEN; kb += V*span)
	
	add S_kb, S_kb, S_V_x_span     // kb += V * span
	cmp c0, S_kb, S_fft_len       // c0 = compare(kb, fft_len)

	blt c0, for_kb_loop               // while kb < fft_len
	vst.4 V_y3, S_temp, S_span    // complex_vector_write(y3, A, kb + j + 3*quarter, span)

	//
	// end for(j = 0; j < quarter; j++)
	//

	add S_j, S_j, 1
	cmp c0, S_j, S_quarter
	blt c0, for_j_loop_early
	nop

	//
	// end for(s = 1; s <= EFF_LOG4V; s++)
	//

	add S_s, S_s, 1
	cmp c0, S_s, EFF_LOG4V
	ble c0, for_s_loop_early
	drain      // Store fence
	
	// for(s = LOG4V + 1; s <= log4(N); s++) {

for_s_loop_late:	
	// late stage: contiguous within a block, twiddle vectors
	//
	// span    = 4^stage
	// quarter = span / 4

	lsl S_span, S_s, 1          // span = 2*s
	ldi S_quarter, 1
	lsl S_span, S_quarter, S_span   // span = 1<<(2*s) = 4^s
	lsr S_quarter, S_span, 2    // quarter = span/4
	lsl S_delta, S_quarter, 2     // delta = 4 * quarter
	lsl S_2_x_delta, S_delta, 1     // 2_x_delta = 8 * quarter
	lsl S_index_mult, S_s, 1    // index_mult = 2*s
	lsr S_index_mult, S_fft_len, S_index_mult  // index_mult = FFT_LEN/4^s = FFT_LEN/span
		
#define S_k              s16
#define S_4kj            s17
#define S_delta_j        s18
#define S_delta_delta_j  s19
#define S_w_stride       s20
	
	// Pseudo: for j = 0, V, 2V, ... quarter-V:
	//
	// for(j = 0; j < quarter; j += V) {

	clear(S_j)

	//
	// delta_j = j * index_mult = j * fft_len>>(2*s)
	// Because j increments by V:
	// delta_delta_j = V * fft_len>>(2**s)
	//   = (1<<LOG2V) * fft_len>>(2*s)
	//   = (1<<LOG2V) * ((1<<(2*log4(N)))>>(2*s))
	//   = (1<<LOG2V) * (1<<(2*(log4(N) - s)))
	//   = 1<<(LOG2V + 2*(log4(N) - s))
	//

	sub S_delta_delta_j, S_LOG4N, S_s
	lsl S_delta_delta_j, S_delta_delta_j, 1
	add S_delta_delta_j, S_delta_delta_j, EFF_LOG2V
	ldi S_temp, 1
	lsl S_delta_delta_j, S_temp, S_delta_delta_j
	lsl S_delta_delta_j, S_delta_delta_j, 2     // Multiply by 4 for a byte offset!!

	clear(S_delta_j)

for_j_loop_late:
#ifdef DEBUG
	debug 0xdada
	lsl s50, S_s, 16
	or s50, s50, S_j
	debugr s50
#endif	
	/*
          VLD   w1, [twid1 + j]
          VLD   w2, [twid2 + j]
          VLD   w3, [twid3 + j]
	  
	  complex_vector_read(w1, w, j * index_mult, index_mult, 0x10000);
	  complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult, 0x10000);
	  complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult, 0x10000);
	*/

	add S_temp, S_W, S_delta_j
	move(S_w_stride, S_index_mult)
	vld.4 V_w1, S_temp, S_w_stride // complex_vector_read(w1, w, j * index_mult, index_mult)

	add S_temp, S_temp, S_delta_j
	add S_w_stride, S_w_stride, S_index_mult
	vld.4 V_w2, S_temp, S_w_stride // complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult)
	
	add S_temp, S_temp, S_delta_j
	add S_w_stride, S_w_stride, S_index_mult
	vld.4 V_w3, S_temp, S_w_stride // complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult)

	//
	// Pseudo: for k = 0, span, 2*span, ... N-span:
	//
	// for(k = 0; k < FFT_LEN; k += span)
	//

	clear(S_k)

for_k_loop_late:	
#ifdef DEBUG
	sync
	debug 0xBEEF
	lsl s50, S_s, 16
	or s50, s50, S_j
	debugr s50
	debugr S_kb
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

	add S_4kj, S_k, S_j    // 4kj = k + j
	lsl S_4kj, S_4kj, 2      // 4kj = 4*(k + j)
	
	add S_temp, S_A, S_4kj  // temp = &A[k + j]
	add S_temp, S_temp, S_delta // temp = &A[k + j + quarter]
	vld.4 V_a1, S_temp, 1 // complex_vector_read(a1, A, k + j + quarter, 1)

	add S_temp, S_temp, S_delta // temp = &A[k + j + 2*quarter]
	vld.4 V_a2, S_temp, 1 // complex_vector_read(a2, A, k + j + 2*quarter, 1)
	
	add S_temp, S_temp, S_delta // temp = &A[k + j + 3*quarter]
	vld.4 V_a3, S_temp, 1 // complex_vector_read(a3, A, k + j + 3*quarter, 1)

	add S_temp, S_A, S_4kj  // temp = &A[k + j]
	vld.4 V_a0, S_temp, 1 // complex_vector_read(a0, A, k + j, 1)
	
	/*
                t0 = a0
                VCMUL t1, w1, a1
                VCMUL t2, w2, a2
                VCMUL t3, w3, a3

	complex_vector_mul(t1, w1, a1);
	complex_vector_mul(t2, w2, a2);
	complex_vector_mul(t3, w3, a3);
	*/

	cvmul V_t1, V_w1, V_a1
	cvmul V_t1_2, V_w1_2, V_a1_2
	cvmul V_t1_3, V_w1_3, V_a1_3
	cvmul V_t1_4, V_w1_4, V_a1_4	
	cvmul V_t2, V_w2, V_a2
	cvmul V_t2_2, V_w2_2, V_a2_2
	cvmul V_t2_3, V_w2_3, V_a2_3
	cvmul V_t2_4, V_w2_4, V_a2_4
	cvmul V_t3, V_w3, V_a3
	cvmul V_t3_2, V_w3_2, V_a3_2
	cvmul V_t3_3, V_w3_3, V_a3_3
	cvmul V_t3_4, V_w3_4, V_a3_4
	
	/*
                VCADD s0, t0, t2    VCSUB s1, t0, t2
                VCADD s2, t1, t3    VCSUB s3, t1, t3

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);
	*/

	cvadd V_s0, V_a0, V_t2
	cvadd V_s0_2, V_a0_2, V_t2_2
	cvadd V_s0_3, V_a0_3, V_t2_3
	cvadd V_s0_4, V_a0_4, V_t2_4
	cvsub V_s1, V_a0, V_t2
	cvsub V_s1_2, V_a0_2, V_t2_2
	cvsub V_s1_3, V_a0_3, V_t2_3
	cvsub V_s1_4, V_a0_4, V_t2_4
	cvadd V_s2, V_t1, V_t3
	cvadd V_s2_2, V_t1_2, V_t3_2
	cvadd V_s2_3, V_t1_3, V_t3_3
	cvadd V_s2_4, V_t1_4, V_t3_4
	cvsub V_s3, V_t1, V_t3
	cvsub V_s3_2, V_t1_2, V_t3_2
	cvsub V_s3_3, V_t1_3, V_t3_3
	cvsub V_s3_4, V_t1_4, V_t3_4
	
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

	cvadd V_y0, V_s0, V_s2
	cvadd V_y0_2, V_s0_2, V_s2_2
	cvadd V_y0_3, V_s0_3, V_s2_3
	cvadd V_y0_4, V_s0_4, V_s2_4

	cvsub V_y2, V_s0, V_s2
	cvsub V_y2_2, V_s0_2, V_s2_2
	cvsub V_y2_3, V_s0_3, V_s2_3
	cvsub V_y2_4, V_s0_4, V_s2_4	

	add S_temp, S_A, S_4kj
	vst.4 V_y0, S_temp, 1
	
	cvaddrni V_y1, V_s1, V_s3
	cvaddrni V_y1_2, V_s1_2, V_s3_2
	cvaddrni V_y1_3, V_s1_3, V_s3_3
	cvaddrni V_y1_4, V_s1_4, V_s3_4

	add S_temp, S_temp, S_2_x_delta
	vst.4 V_y2, S_temp, 1
	
	cvaddri V_y3, V_s1, V_s3
	cvaddri V_y3_2, V_s1_2, V_s3_2
	cvaddri V_y3_3, V_s1_3, V_s3_3
	cvaddri V_y3_4, V_s1_4, V_s3_4
	
	sub S_temp, S_temp, S_delta
	vst.4 V_y1, S_temp, 1
	
	/*
                Vst + k+j],           y0
                VST [a + k+j+quarter],   y1
                VST [a + k+j+2*quarter], y2
                VST [a + k+j+3*quarter], y3

	  complex_vector_write(y0, A, k + j, 1, 0x130);
	  complex_vector_write(y1, A, k + j + quarter, 1, 0x130);
	  complex_vector_write(y2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_write(y3, A, k + j + 3*quarter, 1, 0x130);
	*/
	
	add S_temp, S_temp, S_2_x_delta

	// end for(k = 0; k < FFT_LEN; k += span)

	add S_k, S_k, S_span
	cmp c0, S_k, S_fft_len
	blt c0, for_k_loop_late
	vst.4 V_y3, S_temp, 1
	
	// end for(j = 0; j < quarter; j += V) {

	add S_j, S_j, EFF_V
	cmp c0, S_j, S_quarter
	blt c0, for_j_loop_late
	add S_delta_j, S_delta_j, S_delta_delta_j

	// end for(s = LOG4V + 1; s <= log4(N); s++) {

	add S_s, S_s, 1
	cmp c0, S_s, S_LOG4N
	ble c0, for_s_loop_late
	drain      // Store fence

	// Done
	
	epilogue(s3)
	
	ret
	nop
#endif
