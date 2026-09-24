	.export "funktio"
	.export "stop_simulation"
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
	

stop_simulation:
	ldi s0, -1
	jmp s0, 0	// This should stop the simulation with instruction access failure
	nop
	nop
