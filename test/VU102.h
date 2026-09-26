#ifndef VU102_H
#define VU102_H

#define VU102_OP_ADD     0
#define VU102_OP_SUB     0
#define VU102_OP_MUL     1
#define VU102_OP_ADD3    2
#define VU102_OP_MADD    3
#define VU102_OP_ACC     4
#define VU102_OP_MACC    5

#define cvmul     ext VU102_OP_MUL,
#define cvadd     ext VU102_OP_ADD,
#define cvsub     ext VU102_OP_SUB,
#define cvacc     ext VU102_OP_ACC,
#define cvmadd    ext VU102_OP_MADD,
#define cvadd3    ext VU102_OP_ADD3,
#define cvmacc    ext VU102_OP_MACC,

#define cvbmul     extb VU102_OP_MUL,
#define cvbadd     extb VU102_OP_ADD,
#define cvbsub     extb VU102_OP_SUB,
#define cvbacc     extb VU102_OP_ACC,
#define cvbmadd    extb VU102_OP_MADD,
#define cvbadd3    extb VU102_OP_ADD3,
#define cvbmacc    extb VU102_OP_MACC,

#endif
