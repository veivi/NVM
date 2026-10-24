///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
// 
// PROPRIETARY AND CONFIDENTIAL.
// Unauthorized copying, modification, or distribution of this file, 
// via any medium, is strictly prohibited.
//
///////////////////////////////////////////////////////////////////////////////
	
	.export "funktio"
	.export "stop_simulation"
	.import "init"

	.section "code"

stop_simulation:
	drain
	debug -1

stop_loop:
	br stop_loop
	nop

fft_debug:	
	lsl s50, s3, 16
	lsl s51, s7, 8
	or s50, s50, s51
	or s50, s50, s9
	ret
	debugr s50
	

	
