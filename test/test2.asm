	.export "funktio"
	.export "stop_simulation"
	.import "init"

	.section "code"

alku:
	jmpal init
	nop

funktio:
	ret
	nop
	
loop:
	ba loop
	nop
	

stop_simulation:
	drain
	debugi -1

stop_loop:
	ba stop_loop
	nop

	

