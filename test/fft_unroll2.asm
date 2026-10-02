	.export "fft_dit_unroll2"
	.import "w_table"

#include <VU102.h>
#include <common.h>

	.section "code"

fft_dit_unroll2:
	debug 96
	
	// Params: s1 = data, s2 = log2(N)

	// for(s = 1; s <= EFF_LOG2V; s++) {
	//   m = 1<<s;
	//   half_m = m/2;
	//   tab_step = 1<<(LOG2LEN - s);

	ldi s3, 1          // s3 = "s" = 1
	lsl s15, s3, s2    // s15 = 1<<LOG2LEN = FFT_LEN
	ldi s17, w_table   // s17 points to w_table

for_s_loop_early:
	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsr s5, s4, 1  // s5 = "half_m" = m/2
	sub s6, s2, s3  // s6 = "log2_tab_step" = LOG2LEN - s
	
	//
	// Early stage: our vectors will handle k with striding by m
	//
	//     for(j = 0; j < half_m; j++) {
	
	clear(s7)	  // s7 = "j" = 0

for_j_loop:
	// 	complex_t omega = w[j * tab_step];
	
	lsl s8, s7, s6    // s8 = j<<log2_tab_step = j * tab_step
	ldx s8, s17, s8   // s8 = "omega" =  w[j * tab_step]
	
	// 	for(v = 0; v < FFT_LEN; v += EFF_V*m) {
	
	clear(s9)         // s9 = "v" = 0
	
for_v_loop_early:
	lsl s50, s3, 16
	lsl s51, s7, 8
	or s50, s50, s51
	or s50, s50, s9
	debugr s50
	
	// 	  complex_t a[V], t[V], u[V], x[V];
	// 	  complex_vector_read(u, A, j + v, m);

	add s10, s7, s9    // s10 = j + v
	lsl s10, s10, 2   // s10 = 4*(j + v)
	add s10, s10, s1   // s10 = &A[j + v]
	vld2 v0, s10, s4   // v0-1 = "u" = complex_vector_read(A, j + v, m)
	
	// 	  complex_vector_read(a, A, j + v + half_m, m);

	lsl s12, s5, 2     // s12 = 4*half_m
	add s13, s10, s12  // s13 =  &A[j + v + half_m]
	vld2 v2, s13, s4   // v2-3 = "a" = complex_vector_read(A, j + v + half_m, m)

	// 	  complex_vector_mul_bc(t, a, &omega);

	lsl s14, s4, EFF_LOG2V // s14 = m<<EFF_LOG2V = EFF_V*m
	add s9, s9, s14     // v += EFF_V*m
	cmp c1, s9, s15     // c1 = compare(v, FFT_LEN)
	
	cvbmul v2, v2, s8  // v2-3 = "t" = complex_vector_mul_bc(a, &omega)
	cvbmul v3, v3, s8
	
	// 	  complex_vector_add(x, u, t);
	// 	  complex_vector_sub(y, u, t);

	cvadd v4, v0, v2   // v2-3 = "x" = complex_vector_add(u, t)
	cvadd v5, v1, v3
	
	cvsub v6, v0, v2   // v4-5 = "y" = complex_vector_sub(u, t)
	cvsub v7, v1, v3   
	
	// 	  complex_vector_write(x, A, j + v, m);
	// 	  complex_vector_write(y, A, j + v + half_m, m);
	
	vst2 v4, s10, s4           // complex_vector_write(x, A, j + v, m)
	blt c1, for_v_loop_early  // Loop as long as v < FFT_LEN
	vst2 v6, s13, s4           // complex_vector_write(y, A, j + v + half_m, m)

end_for_v_loop_early:
	add s7, s7, 1         // j++
	cmp c0, s7, s5
	blt c0, for_j_loop     // while j < half_m
	nop

end_for_j_loop:
	add s3, s3, 1    // s = s + 1
	cmp c1, s3, EFF_LOG2V  
	ble c1, for_s_loop_early   // while s <= EFF_LOG2V
	drain  // Delay slot

	//
	// Late stage: our vectors will handle j directly, striding used only for w
	//
	// for(s = EFF_LOG2V+1; s <= LOG2LEN; s++) {

for_s_loop_late:
	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsr s5, s4, 1  // s5 = "half_m" = m/2
	sub s6, s2, s3  // s6 = "log2_tab_step" = LOG2LEN - s
	
	ldi s16, 1
	lsl s16, s16, s6  // s16 = 1<<log2_tab_step = tab_step
	
	//     for(k = 0; k < FFT_LEN; k += m) {
	
	clear(s7)	  // s7 = "k" = 0
	
for_k_loop:		
	// 	for(v = 0; v < half_m; v += EFF_V) {

	clear(s9)         // s9 = "v" = 0
	
for_v_loop_late:	
	lsl s50, s3, 16
	lsl s51, s7, 8
	or s50, s50, s51
	or s50, s50, s9
	debugr s50
	
	// 	  complex_t omega[V], a[V], t[V], u[V], x[V];
	// 	  complex_vector_read(omega, w, v * tab_step, tab_step);

	lsl s8, s9, s6  // s8 = v<<log2_tab_step = v * tab_step
	lsl s8, s8, 2   // s8 = 4*v*tab_step
	add s8, s17, s8  // s8 = &w_table[v * tab_step]
	vld2 v0, s8, s16  // v0-1 = "omega" = complex_vector_read(w, v * tab_step, tab_step)
	
	// 	  complex_vector_read(u, A, k + v, 1);
	
	add s10, s7, s9    // s10 = k + v
	lsl s10, s10, 2   // s10 = 4*(k + v)
	add s10, s10, s1   // s10 = &A[k + v]

	vld2 v2, s10, 1    // v2-3 = "u" = complex_vector_read(A, k + v, 1);

	//        complex_vector_read(a, A, k + v + half_m, 1);
	
	lsl s12, s5, 2     // s12 = 4*half_m
	add s13, s10, s12  // s13 =  &A[k + v + half_m]
	
	vld2 v4, s13, 1     // v4-5 = "a" = complex_vector_read(A, k + v + half_m, 1);
	
	add s9, s9, EFF_V           // v += EFF_V
	cmp c1, s9, s5
	
	cvmul v4, v4, v0   // v4-5 = "t" = complex_vector_mul(t, a, omega)
	cvmul v5, v5, v1
	
	// 	  complex_vector_add(x, u, t);

	cvadd v6, v2, v4	
	cvadd v7, v3, v5

	// 	  complex_vector_sub(x, u, t);
	
	cvsub v8, v2, v4	
	cvsub v9, v3, v5
	
        // 	  complex_vector_write(x, A, k + v, 1)
	
	vst2 v6, s10, 1
	blt c1, for_v_loop_late  // while v < half_m
	vst2 v8, s13, 1           // complex_vector_write(x, A, k + v + half_m + V, 1)
	
end_for_v_loop_late:
	add s7, s7, s4           // k += m
	cmp c0, s7, s15
	blt c0, for_k_loop       // while k < FFT_LEN
	nop

end_for_k_loop:	
	add s3, s3, 1    // s = s + 1
	cmp c0, s3, s2   
	ble c0, for_s_loop_late // while s <= LOG2LEN
	drain   // Delay slot

	// Done

	ret
	nop
	
