	.export "fft_decimation_in_time"
	.import "stop_simulation"

#include <VU102.h>
#include <common.h>

	.section "code"

fft_decimation_in_time:
	debugi 48
	
	// Params: s1 = data, s2 = log2(N)

	// for(s = 1; s <= LOG2LEN; s++) {
	//   m = 1<<s;
	//   half_m = m/2;
	//   tab_step = 1<<(LOG2LEN - s);

	ldi s3, 1          // s3 = "s" = 1
	lsl s15, s3, s2    // s15 = 1<<LOG2LEN = FFT_LEN
	ldi s17, w_table   // s17 points to w_table

for_s_loop_early:
	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsri s5, s4, 1  // s5 = "half_m" = m/2
	
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
	
	// 	for(v = 0; v < FFT_LEN; v += V*m) {
	
	clear(s9)         // s9 = "v" = 0
	
for_v_loop_early:
	// 	  complex_t a[V], t[V], u[V], x[V];
	// 	  complex_vector_read(u, A, j + v, m);

	add s10, s7, s9    // s10 = j + v
	lsli s10, s10, 2   // s10 = 4*(j + v)
	add s10, s10, s1   // s10 = &A[j + v]
	vld v0, s10, s4   // v0 = "u" = complex_vector_read(A, j + v, m)
	
	// 	  complex_vector_read(a, A, j + v + half_m, m);

	lsli s12, s5, 2     // s12 = 4*half_m
	add s13, s10, s12  // s13 =  &A[j + v + half_m]
	vld v1, s13, s4   // v1 = "a" = complex_vector_read(A, j + v + half_m, m)

	// 	  complex_vector_mul_bc(t, a, &omega);

	lsli s14, s4, LOG2V // s14 = m<<LOG2V = V*m
	add s9, s9, s14     // v += V*m
	cmp c1, s9, s15     // c1 = compare(v, FFT_LEN)
	
	cvbmul v1, v1, s8  // v1 = "t" = complex_vector_mul_bc(a, &omega)
	
	// 	  complex_vector_add(x, u, t);
	// 	  complex_vector_sub(y, u, t);

	cvadd v2, v0, v1   // v2 = "x" = complex_vector_add(u, t)
	cvsub v3, v0, v1   // v3 = "y" = complex_vector_sub(u, t)
	
	// 	  complex_vector_write(x, A, j + v, m);
	// 	  complex_vector_write(y, A, j + v + half_m, m);
	
	vst v2, s10, s4           // complex_vector_write(x, A, j + v, m)
	
	blt c1, for_v_loop_early  // Loop as long as v < FFT_LEN
	vst v3, s13, s4           // complex_vector_write(y, A, j + v + half_m, m)

end_for_v_loop_early:
	addi s7, s7, 1         // j++

	cmp c0, s7, s5
	blt c0, for_j_loop     // while j < half_m
	nop

end_for_j_loop:
	drain
	
	addi s3, s3, 1    // s = s + 1
	cmpi c0, s3, LOG2V  
	ble c0, for_s_loop_early   // while s < LOG2V
	nop

for_s_loop_late:
	//
	// Late stage: our vectors will handle j directly, striding used only for w
	//

	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsri s5, s4, 1  // s5 = "half_m" = m/2
	sub s6, s2, s3  // s6 = "log2_tab_step" = LOG2LEN - s
	
	ldi s16, 1
	lsl s16, s16, s6  // s16 = 1<<log2_tab_step = tab_step
	
	//     for(k = 0; k < FFT_LEN; k += m) {
	
	clear(s7)	  // s7 = "k" = 0
	
for_k_loop:		
	// 	for(v = 0; v < half_m; v += V) {

	clear(s9)         // s9 = "v" = 0
	
for_v_loop_late:	
	// 	  complex_t omega[V], a[V], t[V], u[V], x[V];
	// 	  complex_vector_read(omega, w, v * tab_step, tab_step);

	lsl s8, s9, s16  // s8 = v<<log2_tab_step = v * tab_step
	add s8, s17, s8  // s8 = &w_table[v * tab_step]
	vld v0, s8, s16  // v0 = "omega" = complex_vector_read(w, v * tab_step, tab_step)
	
	// 	  complex_vector_read(u, A, k + v, 1);
	
	add s10, s7, s9    // s10 = k + v
	lsli s10, s10, 2   // s10 = 4*(k + v)
	add s10, s10, s1   // s10 = &A[k + v]

	vldi v1, s10, 1    // v1 = "u" = complex_vector_read(A, k + v, 1);

	//        complex_vector_read(a, A, k + v + half_m, 1);
	
	lsli s12, s5, 2     // s12 = 4*half_m
	add s13, s10, s12  // s13 =  &A[k + v + half_m]
	
	vldi v2, s13, 1     // v2 = "a" = complex_vector_read(A, k + v + half_m, 1);
	
	// 	  complex_vector_mul(t, u, omega);

	addi s9, s9, V           // v += V
	cmp c0, s9, s5
	
	cvmul v2, v2, v0   // v2 = "t" = complex_vector_mul(t, a, omega)
	
	// 	  complex_vector_add(x, u, t);
        // 	  complex_vector_write(x, A, k + v, 1)

	cvadd v3, v1, v2
	vsti v3, s10, 1
	
	// 	  complex_vector_sub(y, u, t);
	
	cvsub v4, v1, v2
	
	blt c0, for_v_loop_late  // Loop as long as v < half_m
	vsti v4, s13, 1          // 	  complex_vector_write(y, A, k + v + half_m, 1)
	
end_for_v_loop_late:
	add s7, s7, s4           // k += m
	cmp c0, s7, s15
	blt c0, for_k_loop       // While k < FFT_LEN
	nop

end_for_k_loop:
	drain
	
	addi s3, s3, 1    // s = s + 1
	cmp c0, s3, s2   // if(s <= LOG2LEN)
	ble c0, for_s_loop_late
	nop

	// Read result

	debugi 64
	ldi s3, 1
	lsl s3, s3, s2
	
read_loop:
	ld s2, s1, 0
	addi s1, s1, 4
	subi s3, s3, 1
	cmpi c0, s3, 0
	bgt c0, read_loop
	nop
	
	// Done

	ret
	nop
	
	.section "const"

w_table:
	.word 1024
	
