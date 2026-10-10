#ifndef COMMON_H
#define COMMON_H

#define clear(s)    and s, s, 0
#define vclear(v)   vand v, v, 0
#define move(d, s)  and d, s, s
#define vmove(d, s) vand d, s, s

#define load_big(s, v)   ldih s, $hi(v) \
    or s, s, $lo(v)

#endif
