#!/bin/bash

design/range.sh "12" "8" "2 4 8"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

design/range.sh "12" "16" "2 4"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

design/range.sh "10" "4" "4"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

design/range.sh "8 10" "2 4 8 16" "1 2 4"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

