///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
// 
// PROPRIETARY AND CONFIDENTIAL.
// Unauthorized copying, modification, or distribution of this file, 
// via any medium, is strictly prohibited.
//
///////////////////////////////////////////////////////////////////////////////
  
#ifndef COMMON_H
#define COMMON_H

#define clear(s)         and s, s, 0
#define vclear(v)        vand v, v, 0
#define move(d, s)       and d, s, s
#define vmove(d, s)      vand d, s, s
#define load_big(s, v)   ldih s, $hi(v) \
                         or s, s, $lo(v)
//
// Single register push/pop
//

#define sp               s0

#define push(s)          sub sp, sp, 4 \
                         st s, sp, 0
#define pop(s)           ld s, sp, 0 \
			 add sp, sp, 4

//
// Function prologue and epilogue for nested functions (LR saved on stack)
//   Parameter s specifies the register to be used as scratch
//   z1 = link register

#define prologue(s)      mfsys s, z1   \
                         sub sp, sp, 4 \
                         st s, sp, 0

#define epilogue(s)      ld s, sp, 0 \
                         mtsys z1, s  \
			 add sp, sp, 4

#endif
