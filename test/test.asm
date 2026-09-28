	.import "funktio"
	.import "fft_decimation_in_time"
	.import "stop_simulation"
	.export "init"
	.export "w_table"

#include <common.h>
#include <VU102.h>
	
	.section "bss"

bss_start:	
	.byte 5

	.align 16
test:	
	.long 1
	.short 10
	.word 1
	
	.align 4
	
vektoridata_alku:
	.long 64
vektoridata_loppu:

fft_data:
	.long 64

	.align 32  // Force the section to be multiple of vector size
	
bss_end:	
	
	.section "data"

merkkijono:	
	.string "Paska merkkijono\0"
	
	.section "const"

w_table:
	.long 64

test_data:
	.long 64
	
	.section "code"
	
init:
	ldi s1, bss_start
	ldi s2, bss_end
	sub s2, s2, s1

	vclear(v0)

clear_bss_loop:
	vsti v0, s1, 1
	subi s2, s2, 32
	bgt c0, clear_bss_loop
	addi s1, s1, 32

tests_start:	
	// ba write_neg_bytes
	nop
	
	// Initialize fft_data with the test signal

	ldi s0, test_data
	ldi s1, fft_data
	ldi s2, 64
	
init_fft_loop:
	subi s2, s2, 1
	ldx s3, s0, s2
	bgt c0, init_fft_loop
	stx s3, s1, s2

	// Invoke FFT
	
	ldi s1, fft_data
	jmpal fft_decimation_in_time
	ldi s2, 6

	// Read result

	debugi 64
	drain
	
	ldi s3, 1
	lsl s3, s3, s2
	
read_loop:
	subi s3, s3, 1
	ld s2, s1, 0
	bgt c0, read_loop
	addi s1, s1, 4
	
	// Done
	
	jmpa stop_simulation
	nop
	
write_neg_bytes:	
	ldi s1, bss_start
	ldi s2, 100
	ldi s3, -1

neg_loop:
	stb s3, s1 + 0
	addi s1, s1, 1
	subi s2, s2, 1
	bgt c0, neg_loop
	subi s3, s3, 1

	debugi 256
	
read_neg_bytes:	
	ldi s1, bss_start
	ldi s2, 100
	
byte_read_loop:
	ldb s3, s1 + 0
	ldbu s4, s1 + 1
	ldb s5, s1 + 2
	ldbu s6, s1 + 3
	subi s2, s2, 4
	bgt c0, byte_read_loop
	addi s1, s1, 4

	debugi 257
	
nollataan_vektoridata:	
	ldi s1, vektoridata_alku
	ldi s2, vektoridata_loppu
	sub s2, s2, s1
	ldi s3, 1000

clear_vektori_loop:
	st s3, s1 + 0
	addi s1, s1, 4
	subi s2, s2, 4
	bgt c0, clear_vektori_loop
	addi s3, s3, 2345
	
	// Testataan vector loadeja

	debugi 1
	ldi s1, vektoridata_alku
	
	vldi v0, s1, 1
	vaddi v0, v0, 1
	vsti v0, s1, 1

	vandi v0, v0, 255
	vcmpi vc3, v0, 50
	
	vandi v1, v1, 0  // Clear v1
	vori v1, v1, 3   
	vstib v1, s1, 1  // Write as a sequence of bytes
	vldib v2, s1, 1  // Read back into v2
	vaddi v2, v2, 10
	vstib v2, s1, 1
	vldib v3, s1, 1
	vaddi v3, v3, 1
	vaddi v4, v3, 1
	vaddi v5, v4, 1
	vaddi v6, v5, 1
	vstib v3, s1, 3
	vstib v4, s1, 4
	vstib v5, s1, 5
	vstib v6, s1, 6

	// Memory fence test, first without barriers

	drain
	sync
	
	addi s1, s1, 128
	vaddi v3, v3, 16

	debugi 16
	vstib v3, s1, 10
	vldib v4, s1, 10
	debugi 17

	// Then with write fence
	
	vaddi v3, v3, 16
	
	debugi 32	
	vstib v3, s1, 10
	drain
	vldib v4, s1, 10
	debugi 33	
	
	// Then with read and write fence
	
	vaddi v5, v3, 16
	
	sync
	debugi 48
	vstib v5, s1, 10
	drain
	vldib v6, s1, 10
	sync
	debugi 49

	//
	// Vector Extension test
	//

	addi s1, s1, 128
	
	ldi s2, 3957
	lsli s2, s2, 16
	ori s2, s2, 1060   // s2 = cos(15) + i*sin(15)

	vandi v0, v0, 0
	vbor v0, v0, s2
	vsti v0, s1, 1    // v0 is now all s2 from above

	ldi s2, 1
	lsli s2, s2, 16
	ori s2, s2, 15
	lsli s2, s2, 12   // s2 = 1-i
	vandi v2, v2, 0
	vbor v2, v2, s2   // Load 1-i into v2
	
	debugi 11

	vsti v2, s1, 1
	cvadd v1, v2, v2 // Test saturating complex add
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	cvadd v1, v1, v1
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	cvadd v1, v1, v1
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	cvadd v1, v1, v2
	vsti v1, s1, 1
	
	drain
	debugi 12

	vandi v2, v2, 0  // Load 1.5+0i into v2 
	vori v2, v2, 3
	vlsli v2, v2, 27
	vandi v3, v3, 0  // Load 0-1.5i into v3
	vori v3, v3, 31
	vlsli v3, v3, 11
	vadd v2, v2, v3   // Load 1.5-1.5i into v2
	
	vsti v2, s1, 1
	cvmul v1, v2, v2 // Test saturating complex multiply
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	cvmul v1, v1, v1
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	cvmul v1, v1, v1
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	cvmul v1, v1, v2
	vsti v1, s1, 1
	
	drain
	debugi 13

	vandi v2, v2, 0  // Load 1+0i into v2 
	vori v2, v2, 1
	vlsli v2, v2, 28
	
	// Complex multiply: rotate elements of v2 15 degrees at a time
	
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1

	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1

	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1

	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1
	cvmul v2, v2, v0
	vsti v2, s1, 1    // This should be close to 1 + 0i

	drain
	debugi 10
	
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
	
	vsti v2, s1, 1    // This should be close to 1 + 0i

	drain
	debugi 11

	// Done

	drain
	sync
	
	jmpa stop_simulation
	debugi -1

