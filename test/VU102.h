#ifndef VU102_H
#define VU102_H

#define VU102_OP_MUL      0
#define VU102_OP_ADD      1
#define VU102_OP_SUB      2

#define VU102_OP_MULADD   4
#define VU102_OP_ADD3     5
#define VU102_OP_SUBADD   6

#define VU102_OP_MULACC   8
#define VU102_OP_ACC      9
#define VU102_OP_SUBACC   10

#define cvmul      ext VU102_OP_MUL,
#define cvadd      ext VU102_OP_ADD,
#define cvsub      ext VU102_OP_SUB,
#define cvmuladd   ext VU102_OP_MULADD,
#define cvadd3     ext VU102_OP_ADD3,
#define cvsubadd   ext VU102_OP_SUBADD,
#define cvmulacc   ext VU102_OP_MULACC,
#define cvacc      ext VU102_OP_ACC,
#define cvsubacc   ext VU102_OP_SUBACC,

#define cvbmul      extb VU102_OP_MUL,
#define cvbadd      extb VU102_OP_ADD,
#define cvbsub      extb VU102_OP_SUB,
#define cvbmuladd   extb VU102_OP_MULADD,
#define cvbadd3     extb VU102_OP_ADD3,
#define cvbsubadd   extb VU102_OP_SUBADD,
#define cvbmulacc   extb VU102_OP_MULACC,
#define cvbacc      extb VU102_OP_ACC,
#define cvbsubacc   extb VU102_OP_SUBACC,

#endif
