#!/bin/bash

export ISA=NVM101

log2len=$1
vecsize=$2
unroll=$3
contention=$4

len=$((1<<log2len))

options="-v $vecsize -D FFT_LEN=$len,LOG2FFT_LEN=$log2len --unroll $unroll"

echo "Options: $options"

cc design/test/fft.c -DLOG2LEN=$log2len -DUNROLL=$unroll
./a.out >artefact/fft_ref.txt 

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

echo "Linking $mods"

design/tool/ld.py $mods --map design/test/memory_map.yaml >ld.report

if [ $? -ne 0 ]; then
    echo "Link failed"
    exit 3
fi

echo "Elaborating the test bench..."

nvc -e Testbench -g VecSize_C=$vecsize -gLog2RAMSize_C=13 -gContention_C=$contention

if [ $? -ne 0 ]; then
    echo "NVC elaborate failed"
    exit 4
fi

rm log.txt
rm artefact/sim_log.txt

echo "Starting the simulation..."

nvc >&artefact/sim_log.txt -r Testbench --stop-time=5ms --exit-severity=error --wave=wave.fst # --dump-arrays=10

if [ $? -ne 0 ]; then
    echo "NVC run failed"
    exit 5
fi

id="FFT[$len] V=$vecsize unroll=$unroll contention=$contention"

cmp log.txt reference/ref_$len.txt

if [ $? -ne 0 ]; then
    echo "*** $id FAILED ***"
    exit 10
else
    echo "*** $id IS GOOD ***"
fi

grep "duration =" artefact/sim_log.txt >artefact/result.txt

echo "$id" >>result_table.txt
cat artefact/result.txt >>result_table.txt 


