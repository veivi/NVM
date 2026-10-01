#!/bin/bash

export ISA=NVM101

log2len=$1
vecsize=$2
unroll=$3

len=$((1<<log2len))

options="-v $vecsize -D FFT_LEN=$len,LOG2FFT_LEN=$log2len --unroll $unroll"

echo "Options: $options"

cc design/test/fft.c -DLOG2LEN=$log2len -DUNROLL=$unroll
./a.out

if [ $? -ne 0 ]; then
echo "fft.c failed"
exit 1
fi
   
source="test common fft fft_unroll2 fft_unroll4 fft_unroll8"

for i in $source
do
    mods="$mods $i.obj"
design/tool/as.py $options design/test/$i.asm
if [ $? -ne 0 ]; then
    echo "AS $i failed"
    exit 2
fi

done

echo "Modules to link are $mods"

design/tool/ld.py $mods --map design/test/memory_map.yaml >ld.report

if [ $? -ne 0 ]; then
    echo "Link failed"
    exit 3
fi

nvc -e Testbench -g VecSize_C=$vecsize

if [ $? -ne 0 ]; then
    echo "NVC elaborate failed"
    exit 4
fi

rm log.txt
rm artefact/sim_log.txt

nvc >&artefact/sim_log.txt -r Testbench --stop-time=5ms --exit-severity=error --wave=wave.fst # --dump-arrays=10

if [ $? -ne 0 ]; then
    echo "NVC run failed"
    exit 5
fi

cmp log.txt reference/ref_$len.txt

if [ $? -ne 0 ]; then
    echo "*** Reference comparison FAILED ***"
    exit 10
else
    echo "*** SUCCESS!! ***"
fi

grep "duration =" artefact/sim_log.txt >artefact/result.txt

echo "FFT[$len] V=$vecsize unroll=$unroll" >>result_table.txt
cat artefact/result.txt >>result_table.txt 


