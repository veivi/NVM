	.import "funktio"
	.import "stop_simulation"
	.export "init"

	.section "bss"

bss_start:	
	.byte 5

	.align 16
test:	
	.half 1
	.short 10
	.word 1
	
	.align 4
	
vektoridata_alku:
	.word 32
vektoridata_loppu:

bss_end:	
	
	.section "data"

merkkijono:	
	.string "Paska merkkijono\0"
	
	.section "code"
	
init:
	ldi s1, bss_start
	ldi s2, bss_end
	sub s2, s2, s1
	ldi s3, 0

clear_bss_loop:
	stb s3, s1 + 0
	stb s3, s1 + 1
	stb s3, s1 + 2
	subi s2, s2, 4
	cmpi c0, s2, 0
	bgt c0, clear_bss_loop
	stb s3, s1 + 3
	addi s1, s1, 4

write_neg_bytes:	
	ldi s1, bss_start
	ldi s2, bss_end
	sub s2, s2, s1
	ldi s3, -1

neg_loop:
	stb s3, s1 + 0
	subi s2, s2, 1
	cmpi c0, s2, 0
	bgt c0, neg_loop
	addi s1, s1, 1
	subi s3, s3, 1
		
read_neg_bytes:	
	ldi s1, bss_start
	ldi s2, bss_end
	sub s2, s2, s1
	
byte_read_loop:
	ldb s3, s1 + 0
	ldbu s4, s1 + 1
	ldb s5, s1 + 2
	subi s2, s2, 4
	cmpi c1, s2, 0
	bgt c1, byte_read_loop
	ldbu s6, s1 + 3
	addi s1, s1, 4

nollataan_vektoridata:	
	ldi s1, vektoridata_alku
	ldi s2, vektoridata_loppu
	sub s2, s2, s1
	ldi s3, 1000

clear_vektori_loop:
	st s3, s1 + 0
	subi s2, s2, 4
	cmpi c0, s2, 0
	bgt c0, clear_vektori_loop
	addi s1, s1, 4
	addi s3, s3, 2345
	
	// Testataan vector loadeja

	debugi 1
	ldi s1, vektoridata_alku
	
	vldi v0, s1, 4
	vaddi v0, v0, 1
	vsti v0, s1, 4

	vandi v0, v0, 127
	vcmpi vc3, v0, 64
	
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

	vandi v1, v1, 0
	vandi v3, v3, 0
	vandi v2, v2, 0
	
	vori v2, v2, 1
	vlsli v2, v2, 12
	
	vori v3, v3, 1
	vlsli v3, v3, 28

	vsti v2, s1, 4
	vsti v3, s1, 4
	drain
	debugi 11
	
	ext 1, v1, v2, v3
	vsti v1, s1, 4
	ext 1, v1, v1, v2
	vsti v1, s1, 4
	ext 1, v1, v1, v2
	vsti v1, s1, 4
	ext 1, v1, v1, v2
	vsti v1, s1, 4

	drain
	debugi 10
	
	addi s1, s1, 128
	ldi s2, 10
	ldi s3, 8

	ori s4, s1, 0
vek_init:	
	st s2, s4 + 0
	subi s3, s3, 1
	cmpi c0, s3, 0
	bgt c0, vek_init
	addi s4, s4, 4
	addi s2, s2, 1
	
	vldi v2, s1, 4
	
	ext 100, v1, v2, v3
	vsti v1, s1, 4
	ext 100, v1, v1, v2
	vsti v1, s1, 8
	
	// Finish

	drain
	jmpa stop_simulation
	sync
	debugi -1

