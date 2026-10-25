///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
// 
// PROPRIETARY AND CONFIDENTIAL.
// Unauthorized copying, modification, or distribution of this file, 
// via any medium, is strictly prohibited.
//
///////////////////////////////////////////////////////////////////////////////

	.import "funktio"
	.import "fft_decimation_in_time"
	.import "fft_dit_unroll8"
	.import "fft_dit_unroll4"
	.import "fft_dit_unroll2"
	.import "fft_dit_radix4"
	.import "fft_dit_radix4_unroll2"
	.import "fft_dit_radix4_unroll4"
	.import "stop_simulation"
	.export "init"
	.export "w_table"

#include <common.h>
#include <VU102.h>
	
	.section "bss"

#define STACK_WORDS   100
	
bss_start:	
	
vektoridata_alku:
	.long 64
vektoridata_loppu:

fft_data:
	.long FFT_LEN

	.long STACK_WORDS
top_of_stack:
	
	.align V_BYTES  // Force the section to be multiple of vector size	
bss_end:	
	
	.section "const"

w_table:
	.long FFT_LEN

test_data:
	.long FFT_LEN
	
	.section "code"
	
init:
	// Identify first

	clear(s2)
	clear(s3)
	mtsys z0, s2  // Clear ID pointer
	ldi s1, 8
	
id_loop:
	mfsys s2, z0  // Read ID
	st s2, s3, 0
	sub s1, s1, 1
	bge (c0), id_loop
	add s3, s3, 4
	
	// Initialize stack pointer
	
	load_big(sp, top_of_stack)

	// Clear BSS data
	
	load_big(s1, bss_start)
	load_big(s2, bss_end)
	sub s2, s2, s1

	vclear(v0)

clear_bss_loop:
	vst v0, s1, 1
	sub s2, s2, V_BYTES
	bgt (c0), clear_bss_loop
	add s1, s1, V_BYTES

tests_start:
	// ba test_ldpc
	// ba write_neg_bytes
	nop
	
	// Initialize fft_data with the test signal

	load_big(s1, test_data)
	load_big(s2, fft_data)
	load_big(s3, FFT_LEN)
	lsr s3, s3, LOG2V
	
init_fft_loop:
	vld v0, s1, 1
	add s1, s1, V_BYTES
	sub s3, s3, 1
	vst v0, s2, 1
	bgt (c0), init_fft_loop
	add s2, s2, V_BYTES

	// Drain!!

	drain
	
	// Invoke FFT

	debug 0x57A7     // Stopwatch start
	
	load_big(s1, fft_data)

#ifdef RADIX4
	ldi s2, LOG2FFT_LEN
#if UNROLL_K < 2
	br.l fft_dit_radix4
#elif UNROLL_K < 4
	br.l fft_dit_radix4_unroll2
#elif UNROLL_K < 8
	br.l fft_dit_radix4_unroll4
#endif
	lsr s2, s2, 1
#elif UNROLL_K < 2
	br.l fft_decimation_in_time
#elif UNROLL_K < 4
	br.l fft_dit_unroll2
#elif UNROLL_K < 8
	br.l fft_dit_unroll4
#else
	br.l fft_dit_unroll8
#endif
	ldi s2, LOG2FFT_LEN

	drain
	debug 0x570B     // Stop timer

	// Read result. s1 still points at fft_data which now holds the result

	load_big(s3, FFT_LEN)
	load_big(s4, 0x800000)   // Store to a non-writable address so reported in the log file
	
read_loop:
	ld.8 s8, s1, 0
	add s1, s1, 32
	sub s3, s3, 8
	st.8 s8, s4, 0    
	bgt (c0), read_loop
	add s4, s4, 32
	
	// Done
	
	jmpa stop_simulation
	nop

write_neg_bytes:
	// Test ROTC instruction

	ldi s2, 0
	
	debug 30
	
	ldi s1, 1
	lsl s1, s1, 16
	lsl s1, s1, PRECISION
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	
	drain
	debug 31

	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0

	drain
	debug 30
	
	ldi s1, 1
	lsl s1, s1, 31
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	rotc s1, s1, 1
	st s1, s2, 0
	
	drain
	debug 31

	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0
	rotc s1, s1, -1
	st s1, s2, 0

	drain
	
	// Test scalar instruction predication

	ldi s1, bss_start
	ldi s2, 100
	ldi s3, 30

neg_loop:
	st.b s3, s1 + 0
	add s1, s1, 1
	sub s2, s2, 1
	bgt (c0), neg_loop
	sub s3, s3, 1

	debug 256
	
read_neg_bytes:	
	ldi s1, bss_start
	ldi s2, 100
	
byte_read_loop:
	ld.b s3, s1 + 0
	ld.bu s4, s1 + 1
	ld.b s5, s1 + 2
	ld.bu s6, s1 + 3
	sub s2, s2, 4
	bgt (c0), byte_read_loop
	add s1, s1, 4

	debug 257

	// Test scalar predication: clear values below < -30
	
read_neg_bytes2:	
	ldi s1, bss_start
	ldi s2, 100
	
byte_read_loop2:
	ld.b s3, s1 + 0
	cmp c1, s3, -30
	if lt(c1) sub s3, s3, s3
	st.b s3, s1 + 0
	sub s2, s2, 1
	bgt (c0), byte_read_loop2
	add s1, s1, 1

	debug 258

	
nollataan_vektoridata:	
	ldi s1, vektoridata_alku
	ldi s2, vektoridata_loppu
	sub s2, s2, s1
	ldi s3, 1000

clear_vektori_loop:
	st s3, s1 + 0
	add s1, s1, 4
	sub s2, s2, 4
	bgt (c0), clear_vektori_loop
	add s3, s3, 2345

	
	// Testataan vector loadeja

	debug 1
	ldi s1, vektoridata_alku
	
	vld v0, s1, 1
	vadd v0, v0, 1
	vst v0, s1, 1

	vand v0, v0, 255
	vst v0, s1, 1
	
	vcmp vc3, v0, 50
	if gt(vc3) vsub v0, v0, v0
	vst v0, s1, 1

	drain
	debug 2
	
	vand v1, v1, 0  // Clear v1
	vor v1, v1, 3   
	vst.b v1, s1, 1  // Write as a sequence of bytes
	vld.b v2, s1, 1  // Read back into v2
	vadd v2, v2, 10
	vst.b v2, s1, 1
	vld.b v3, s1, 1
	vadd v3, v3, 1
	vadd v4, v3, 1
	vadd v5, v4, 1
	vadd v6, v5, 1
	vst.b v3, s1, 3
	vst.b v4, s1, 4
	vst.b v5, s1, 5
	vst.b v6, s1, 6

	// Memory fence test, first without barriers

	drain
	sync
	
	add s1, s1, 128
	vadd v3, v3, 16

	debug 16
	vst.b v3, s1, 10
	vld.b v4, s1, 10
	debug 17

	// Then with write fence
	
	vadd v3, v3, 16
	
	debug 32	
	vst.b v3, s1, 10
	drain
	vld.b v4, s1, 10
	debug 33	
	
	// Then with read and write fence
	
	vadd v5, v3, 16
	
	sync
	debug 48
	vst.b v5, s1, 10
	drain
	vld.b v6, s1, 10
	sync
	debug 49

	//
	// Vector Extension test
	//

	add s1, s1, 128
	
	ldi s2, 3957
	lsl s2, s2, 16
	or s2, s2, 1060   // s2 = cos(15) + i*sin(15)

	vand v0, v0, 0
	vbor v0, v0, s2
	vst v0, s1, 1    // v0 is now all s2 from above

	ldi s2, 1
	lsl s2, s2, 16
	or s2, s2, 15
	lsl s2, s2, 12   // s2 = 1-i
	vand v2, v2, 0
	vbor v2, v2, s2   // Load 1-i into v2

	debug 11

	vst v2, s1, 1
	cvadd v1, v2, v2 // Test saturating complex addition
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v1
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v1
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	cvadd v1, v1, v2
	vst v1, s1, 1
	
	debug 11
	
	drain
	debug 39

	vst v2, s1, 1
	cvsub v1, v2, v2 // Test saturating complex subtraction
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	cvsub v1, v1, v2
	vst v1, s1, 1
	
	drain
	debug 40

	vand v3, v3, 0
	cvsub v3, v3, v1   // Test negation of max neg value (which could overflow)
	vst v3, s1, 1
	drain
	
	drain
	debug 12

	
	vand v2, v2, 0  // Load 1.5+0i into v2 
	vor v2, v2, 3
	vlsl v2, v2, 27
	vand v3, v3, 0  // Load 0-1.5i into v3
	vor v3, v3, 31
	vlsl v3, v3, 11
	vadd v2, v2, v3   // Load 1.5-1.5i into v2
	
	vst v2, s1, 1
	cvmul v1, v2, v2 // Test saturating complex multiply
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	cvmul v1, v1, v1
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	cvmul v1, v1, v1
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	cvmul v1, v1, v2
	vst v1, s1, 1
	
	drain
	debug 13

	vand v2, v2, 0  // Load 1+0i into v2 
	vor v2, v2, 1
	vlsl v2, v2, 28
	
	// Complex multiply: rotate elements of v2 15 degrees at a time
	
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1

	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1

	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1

	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1
	cvmul v2, v2, v0
	vst v2, s1, 1    // This should be close to 1 + 0i

	drain
	debug 10
	
	// Try once more
	
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	cvmul v2, v2, v0
	
	vst v2, s1, 1    // This should be close to 1 + 0i

	drain
	debug 11

	// Done

	drain
	sync
	
	jmpa stop_simulation
	debug -1

test_ldpc:
	ldi s1, 0
	ldi s2, 7
	st.b s2, s1, 0
	ldi s2, 8
	st.b s2, s1, 1
	ldi s2, 6
	st.b s2, s1, 2
	ldi s2, 9
	st.b s2, s1, 3
	ldi s2, 8
	st.b s2, s1, 4
	ldi s2, -4
	st.b s2, s1, 5
	ldi s2, 9
	st.b s2, s1, 6
	ldi s2, 7
	st.b s2, s1, 7
	ldi s2, 6
	st.b s2, s1, 8
	ldi s2, 8
	st.b s2, s1, 9
	ldi s2, 7
	st.b s2, s1, 10
	ldi s2, 9
	st.b s2, s1, 11

	drain

	vld.b v0, s1, 1
	add s1, s1, 4
	vld.b v1, s1, 1
	add s1, s1, 4
	vld.b v2, s1, 1
	
	exta 0, v0, v0
	
	exta 1, v0, v0
	exta 1, v1, v0
	exta 1, v2, v0

	ext 2, v3, v0, v0
	ext 2, v4, v1, v0
	ext 2, v5, v2, v0

	ldi s1, 0
	vst.b v3, s1, 1
	add s1, s1, 4
	vst.b v4, s1, 1
	add s1, s1, 4
	vst.b v5, s1, 1
	
	vadd v6, v0, v3
	vadd v7, v1, v4
	vadd v8, v2, v5

	ldi s1, 0
	vst.b v6, s1, 1
	add s1, s1, 4
	vst.b v7, s1, 1
	add s1, s1, 4
	vst.b v8, s1, 1
	
	// Done
	drain
	sync
	jmpa stop_simulation
	nop
