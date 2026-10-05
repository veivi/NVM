#ifndef VU102_H
#define VU102_H

#define VU102_OP_MUL      0
#define VU102_OP_ADD      1
#define VU102_OP_SUB      2
#define VU102_OP_ADDRI    3
#define VU102_OP_ADDRNI   4

#define VU102_OP_MULACC   8
#define VU102_OP_ACC      9
#define VU102_OP_SUBACC   10
#define VU102_OP_ACCRI    11
#define VU102_OP_ACCRNI   12

#define cvmul      ext VU102_OP_MUL,
#define cvadd      ext VU102_OP_ADD,
#define cvaddri    ext VU102_OP_ADDRI,
#define cvaddrni   ext VU102_OP_ADDRNI,
#define cvsub      ext VU102_OP_SUB,
#define cvmulacc   ext VU102_OP_MULACC,
#define cvacc      ext VU102_OP_ACC,
#define cvsubacc   ext VU102_OP_SUBACC,

#define cvbmul      extb VU102_OP_MUL,
#define cvbadd      extb VU102_OP_ADD,
#define cvbaddri    extb VU102_OP_ADDRI,
#define cvbaddrni   extb VU102_OP_ADDRNI,
#define cvbsub      extb VU102_OP_SUB,
#define cvbmulacc   extb VU102_OP_MULACC,
#define cvbacc      extb VU102_OP_ACC,
#define cvbsubacc   extb VU102_OP_SUBACC,

#endif
