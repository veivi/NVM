	.export "funktio"
	.export "stop_simulation"
	.import "init"

	.section "code"

stop_simulation:
	drain
	debugi -1

stop_loop:
	ba stop_loop
	nop


	
