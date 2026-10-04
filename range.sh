#!/bin/bash

log2len=$1
vecsize=$2
unroll=$3

if [[ $# -lt 4 ]]; then
    contention=0.1
    echo "Using default contention value $contention"
else
    contention=$4
fi

for i in $log2len; do
    for j in $vecsize; do
	for k in $unroll; do
	    len=$((1<<$i))

	    echo "Testing FFT[$len] V=$j unrolled by $k"
	    design/run.sh $i $j 2 $k 0 $contention
	    
	    if [ $? -ne 0 ]; then
		echo "Configuration failed!"
		exit 10
	    fi
	done
    done
done

