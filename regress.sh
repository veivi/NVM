#!/bin/bash

#
# FIXED on 2026/10/02: FAIL: large contention!!
#

design/range.sh "8" "2" 2 "1" 0.9

if [ $? -ne 0 ]; then
    exit 10
fi

#
# Radix-4
#

design/range.sh "12" "4" 4 "1" 

if [ $? -ne 0 ]; then
    exit 10
fi

design/range.sh "12" "8" 4 "2" 

if [ $? -ne 0 ]; then
    exit 10
fi

design/range.sh "12" "32" 4 "2" 

if [ $? -ne 0 ]; then
    exit 10
fi

design/range.sh "12" "2" 2 "2 4 8" 0.3

if [ $? -ne 0 ]; then
    exit 10
fi

design/range.sh "12" "8" 2 "2 4 8"

if [ $? -ne 0 ]; then
    exit 10
fi

if [ $? -ne 0 ]; then
    exit 10
fi

design/range.sh "13" "16" 2 "2 4"

if [ $? -ne 0 ]; then
    exit 10
fi

echo "It would seem all tests have PASSED. Huh."
