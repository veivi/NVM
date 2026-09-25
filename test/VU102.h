#ifndef VU102_H
#define VU102_H

#define VU102_OP_ADD     0
#define VU102_OP_MUL     1
#define VU102_OP_ADD3    2
#define VU102_OP_MADD    3
#define VU102_OP_ACC     4
#define VU102_OP_MACC    5

#define cvmul     ext VU102_OP_MUL,
#define cvadd     ext VU102_OP_ADD,
#define cvacc     ext VU102_OP_ACC,
#define cvmadd    ext VU102_OP_MADD,
#define cvadd3    ext VU102_OP_ADD3,
#define cvmacc    ext VU102_OP_MACC,

#endif
