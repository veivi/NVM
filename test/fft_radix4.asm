	.export "fft_dit_radix4"
	.import "w_table"

#include <VU102.h>
#include <common.h>

	.section "code"

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
	lsl reg_span, reg_s, var_span   // span = 1<<(2*s) = 4^s
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

	// C: for(kb = 0; kb < FFT_LEN; kb += V*span) {
	//      printf("---\ns = %d j = %d, kb = %d\n---\n", s, j, kb);
	
#define reg_kb        s13	
#define reg_4kbj      s14	
#define reg_Vspan     s15	
#regine reg_a0        v0
#regine reg_a1        v1
#regine reg_a2        v2
#regine reg_a3        v3
#regine reg_t0        v4
#regine reg_t1        v5
#regine reg_t2        v6
#regine reg_t3        v7
#regine reg_s0        v8
#regine reg_s1        v9
#regine reg_s2        v10
#regine reg_s3        v11
#regine reg_y0        v12
#regine reg_y1        v13
#regine reg_y2        v14
#regine reg_y3        v15
#regine reg_r3n       v16
#regine reg_r3p       v17
	
	clear(reg_kb)
	lsl reg_Vspan, reg_span, LOG2V  // Vspan = span<<LOG2V = V * span

for_kb_loop:
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
	vrotc reg_r3n, reg_s3, -1
	vrotc reg_r3p, reg_s3, 1
	cvadd reg_y1, reg_s1, reg_r3n
	cvsub reg_y3, reg_s1, reg_r3p

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

	add reg_kb, reg_kb, reg_Vspan     // kb += V * span
	cmp c0, reg_kb, reg_fft_len       // c0 = compare(kb, fft_len)

	blt c0, for_kb_loop               // while kb < fft_len
	vst reg_y3, reg_temp, reg_span    // complex_vector_write(y3, A, kb + j + 3*quarter, span)

for_kb_loop_ends:
	
      }
	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsr s5, s4, 1  // s5 = "half_m" = m/2
	sub s6, s2, s3  // s6 = "log2_tab_step" = LOG2LEN - s
    // span    = 4^stage
    // quarter = span / 4

    // if quarter >= V:
    
    if(quarter >= V) {
      // late stage: contiguous within a block, twiddle vectors

      // for k = 0, span, 2*span, ... N-span:

      for(k = 0; k < FFT_LEN; k += span) {
	
	// for j = 0, V, 2V, ... quarter-V:

	for(j = 0; j < quarter; j += V) {
	  
	  printf("---\ns = %d k = %d j = %d\n---\n", s, k, j);
	
	  /*
                VLD   a0, [a + k+j]
                VLD   a1, [a + k+j+quarter]
                VLD   a2, [a + k+j+2*quarter]
                VLD   a3, [a + k+j+3*quarter]
                VLD   w1, [twid1 + j]
                VLD   w2, [twid2 + j]
                VLD   w3, [twid3 + j]
	  */

	  complex_vector_read(a0, A, k + j, 1, 0x130);
	  complex_vector_read(a1, A, k + j + quarter, 1, 0x130);
	  complex_vector_read(a2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_read(a3, A, k + j + 3*quarter, 1, 0x130);
	  
	  complex_vector_read(w1, w, j * index_mult, index_mult, 0x10000);
	  complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult, 0x10000);
	  complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult, 0x10000);

	  /*
                t0 = a0
                VCMUL t1, w1, a1
                VCMUL t2, w2, a2
                VCMUL t3, w3, a3
	  */

	  complex_vector_mul(t1, w1, a1);
	  complex_vector_mul(t2, w2, a2);
	  complex_vector_mul(t3, w3, a3);

	  /*
                VCADD s0, t0, t2    VCSUB s1, t0, t2
                VCADD s2, t1, t3    VCSUB s3, t1, t3
	  */

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);

	  /*
                VCADD y0, s0, s2
                VCSUB y2, s0, s2
                VROTNJ r3n, s3      VROTJ r3p, s3
                VCADD y1, s1, r3n
                VCADD y3, s1, r3p
	  */

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);
	  
	  /*
                VST [a + k+j],           y0
                VST [a + k+j+quarter],   y1
                VST [a + k+j+2*quarter], y2
                VST [a + k+j+3*quarter], y3
	  */

	  complex_vector_write(y0, A, k + j, 1, 0x130);
	  complex_vector_write(y1, A, k + j + quarter, 1, 0x130);
	  complex_vector_write(y2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_write(y3, A, k + j + 3*quarter, 1, 0x130);

	}
      }
    } else {
    }
    
    //STORE_FENCE   // required once per radix-4 stage, same cross-stage RAW hazard as before
  }
