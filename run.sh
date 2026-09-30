#!/bin/sh

export ISA=NVM101

options="-v 4 -D FFT_LEN=32,LOG2FFT_LEN=5 --unroll 1"

design/tool/as.py $options design/test/test.asm
design/tool/as.py $options design/test/fft.asm
design/tool/as.py $options design/test/fft_unroll4.asm
design/tool/as.py $options design/test/fft_unroll2.asm
design/tool/as.py $options design/test/common.asm
design/tool/ld.py test.obj fft.obj fft_unroll4.obj fft_unroll2.obj common.obj --map design/test/memory_map.yaml >ld.report

nvc -e Testbench
nvc -r Testbench --stop-time=5ms --exit-severity=error --wave=wave.fst --dump-arrays=10

