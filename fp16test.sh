#!/bin/bash


design/analyze.sh

if [ $? -ne 0 ]; then
    echo "Analysis failed"
    exit 1
fi

nvc -e FP16Testbench
nvc -r FP16Testbench

