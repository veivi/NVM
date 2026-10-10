#ifndef COMMON_H
#define COMMON_H

#define sp               s0

#define clear(s)         and s, s, 0
#define vclear(v)        vand v, v, 0
#define move(d, s)       and d, s, s
#define vmove(d, s)      vand d, s, s
#define load_big(s, v)   ldih s, $hi(v) \
                         or s, s, $lo(v)
//
// Single register push/pop
//

#define push(s)          sub s0, s0, 4 \
                         st s, s0, 0
#define pop(s)           ld s, s0, 0 \
			 add s0, s0, 4

//
// Function prologue and epilogue for nested functions (stores LR onto stack)
//

#define prologue(s)      mflr s \
                         sub sp, sp, 4 \
                         st s, sp, 0

#define epilogue(s)      ld s, sp, 0 \
			 mtlr s \
			 add sp, sp, 4

#endif
