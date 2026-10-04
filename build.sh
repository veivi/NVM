#!/bin/bash

source="test common fft fft_unroll2 fft_unroll4 fft_unroll8 fft_radix4"

export ISA=NVM101

log2len=$1
vecsize=$2
unroll=$3
precision=$4
radix=$5

len=$((1<<log2len))

defs="PRECISION=$precision,DEBUG=1,FFT_LEN=$len,LOG2FFT_LEN=$log2len"

if [ $radix -gt 2 ]; then
    defs="$defs,RADIX4=1"
fi

options="-v $vecsize -D $defs --unroll $unroll"

echo "Software build options: $options"

for i in $source
do
    # echo "Compiling module $i"
    
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

