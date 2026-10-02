#!/bin/bash

log2len=$1
vecsize=$2
unroll=$3
contention=$4

len=$((1<<log2len))

echo "Compiling and running the C reference..."

cc design/test/fft.c -DLOG2LEN=$log2len -DUNROLL=$unroll

if [ $? -ne 0 ]; then
    echo "Compiling fft.c failed"
    exit 1
fi

./a.out >artefact/fft_ref.txt 

if [ $? -ne 0 ]; then
    echo "Running fft.c failed"
    exit 1
fi

echo "Building the software..."

design/build.sh $log2len $vecsize $unroll $contention

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

echo "Extracting bss_end from the linker report..."

report=$(grep "test.obj:bss_end" ld.report)
report=($report)
bss_end=${report[3]}
echo "  bss_end = $bss_end"

echo "Elaborating the test bench..."

nvc -e Testbench -g VecSize_C=$vecsize -gLog2RAMSize_C=14 -gRAMSize_C=$bss_end -gContention_C=$contention

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

cmp log.txt reference.txt    # reference/ref_$len.txt

if [ $? -ne 0 ]; then
    echo
    echo "###########################################################################"
    echo "###                                                                      "
    echo "###  FAIL    FAIL    FAIL    FAIL    FAIL    FAIL    FAIL    FAIL    FAIL"
    echo "###                                                                      "
    echo "###      $id COMPARISON FAILED"
    echo "###                                                                      "
    echo "###   FAILURE NO GOOD. FAILURE BAD. NO BUENO. THIS IS NOT HOW YOU DO FFT."
    echo "###                                                                      "
    echo "###########################################################################"
    echo
    
    exit 10
else
    echo "*** $id IS GOOD ***"
fi

grep "duration =" artefact/sim_log.txt >artefact/result.txt

echo "$id" >>result_table.txt
cat artefact/result.txt >>result_table.txt 


