	.export "funktio"
	.import "init"

	.section "code"

alku:
	jmpal init

funktio:
	// jmp s0
	nop
	nop
	
loop:
	ba loop
	
