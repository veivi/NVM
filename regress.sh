#!/bin/bash

design/range.sh "12" "2 4 8" "8"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

exit

design/range.sh "12" "8 16" "2 4"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

exit

design/range.sh "8 10" "8 16" "1 2 4"

if [ $? -ne 0 ]; then
    echo "Configuration range failed!"
    exit 10
fi

