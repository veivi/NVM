#ifndef COMMON_H
#define COMMON_H

#define clear(s)         and s, s, 0
#define vclear(v)        vand v, v, 0
#define move(d, s)       and d, s, s
#define vmove(d, s)      vand d, s, s
#define load_big(s, v)   ldih s, $hi(v) \
                         or s, s, $lo(v)
#define push(s)          sub s0, s0, 4 \
                         st s, s0, 0
#define pop(s)           ld s, s0, 0 \
			 add s0, s0, 4
#endif
