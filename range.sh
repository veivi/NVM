#!/bin/bash

log2len=$1
vecsize=$2
radix=$3
unroll=$4

debug=0

if [[ $# -lt 5 ]]; then
    contention=0.1
    echo "Using default contention value $contention"
else
    contention=$5
fi

for i in $log2len; do
    for j in $vecsize; do
	for k in $unroll; do
	    len=$((1<<$i))

	    echo "Testing FFT[$len] V=$j unrolled by $k"
	    design/run.sh $i $j $radix $k $debug $contention
	    
	    if [ $? -ne 0 ]; then
		echo "Configuration failed!"
		exit 10
	    fi
	done
    done
done

