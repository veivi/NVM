	.export "fft_decimation_in_time"
	.import "stop_simulation"

#include <VU102.h>
#include <common.h>
	
	.section "code"
	
fft_decimation_in_time:
	// Params: s1 = data, s2 = log2(N)
	
	// for(s = 1; s <= LOG2LEN; s++) {
	//   m = 1<<s;
	//   half_m = m/2;
	//   tab_step = 1<<(LOG2LEN - s);

	ldi s3, 1   // s3 will hold "s"
	lsl s15, s3, s2  // s5 = 1<<LOG2LEN = FFT_LEN

for_s_loop:
	debugi 12
	
	ldi s4, 1
	lsl s4, s4, s3  // s4 = "m" = 1<<s
	lsri s5, s4, 1  // s5 = "half_m" = m/2
	sub s6, s2, s3  // s6 = "log2_tab_step" = LOG2LEN - s
	addi s6, s6, 2  // s6 = "log2_tab_step_bytes" = log2_tab_step + 2
	
	//   if(half_m < V) {
	
	cmpi c0, s5, V
	bge c0, late_stage
	nop
	nop
	
	//
	// Early stage: our vectors will handle k with striding by m
	//

	//     for(j = 0; j < half_m; j++) {
	
	clear(s7)	  // s7 = "j" = 0

for_j_loop:
	debugi 13
	// 	complex_t omega = w[j * tab_step];
	
	lsl s8, s7, s6    // s8 = j<<log2_tab_step_bytes = j * tab_step_bytes
	ld s8, s8, w_table  // s8 = "omega" =  w[j * tab_step]
	
	// 	for(v = 0; v < FFT_LEN; v += V*m) {
	
	clear(s9)         // s9 = "v" = 0
	
for_v_loop:
	debugi 14
	// 	  complex_t a[V], t[V], u[V], x[V];
	// 	  complex_vector_read(u, A, j + v, m);

	add s10, s7, s9    // s10 = j + v
	lsli s10, s10, 2   // s10 = 4*(j + v)
	add s10, s10, s1   // s10 = &A[j + v]
	lsli s11, s4, 2     // s11 = 4*m
	vld v0, s10, s11   // v0 = "u" = complex_vector_read(A, j + v, m)
	
	// 	  complex_vector_read(a, A, j + v + half_m, m);

	lsli s12, s5, 2     // s12 = 4*half_m
	add s13, s10, s12  // s13 =  &A[j + v + half_m]
	vld v1, s13, s11   // v1 = "a" = complex_vector_read(A, j + v + half_m, m)

	// 	  complex_vector_mul_bc(t, a, &omega);

	cvbmul v1, v1, s8  // v1 = "t" = complex_vector_mul_bc(a, &omega)
	
	// 	  complex_vector_add(x, u, t);
	// 	  complex_vector_sub(y, u, t);

	cvadd v2, v0, v1   // v2 = "x" = complex_vector_add(u, t)
	cvsub v3, v0, v1   // v3 = "y" = complex_vector_sub(u, t)
	
	// 	  complex_vector_write(x, A, j + v, m);
	// 	  complex_vector_write(y, A, j + v + half_m, m);

	debugi 15
	
	lsli s14, s4, LOG2V // s14 = m<<LOG2V = V*m
	add s9, s9, s14    // v += V*m
	cmp c0, s9, s15
	
	blt c0, for_v_loop     // Loop as long as v < FFT_LEN
	vst v2, s10, s11       // complex_vector_write(x, A, j + v, m)
	vst v3, s13, s11       // complex_vector_write(y, A, j + v + half_m, m)
	
	ba s_loop_end
	nop
	nop
	
late_stage:	
	//
	// Late stage: our vectors will handle j directly, striding used only for w
	//

  //     int k = 0;
      
  //     for(k = 0; k < FFT_LEN; k += m) {
  // 	int v = 0;
	
  // 	for(v = 0; v < half_m; v += V) {
  // 	  complex_t omega[V], a[V], t[V], u[V], x[V];
	  
  // 	  complex_vector_read(omega, w, v * tab_step, tab_step);
  // 	  complex_vector_read(a, A, k + v + half_m, 1);
  // 	  complex_vector_mul(t, a, omega);
  // 	  complex_vector_read(u, A, k + v, 1);
  // 	  complex_vector_add(x, u, t);
  // 	  complex_vector_write(x, A, k + v, 1);
  // 	  complex_vector_sub(x, u, t);
  // 	  complex_vector_write(x, A, k + v + half_m, 1);
  // 	}
	//     }
	
s_loop_end:
	debugi 15
	addi s3, s3, 1    // s = s + 1
	cmp c0, s3, s2   // if(s <= LOG2LEN)
	ble c0, for_s_loop
	nop
	nop
	
	// Done
	
	drain
	jmpa stop_simulation
	sync
	debugi -1
	
	jmp s0, 0
	nop
	nop
	
	.section "data"

w_table:
	.word 1024
	
