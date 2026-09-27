#!/bin/sh

nvc -e Testbench
nvc -r Testbench --stop-time=1000us --exit-severity=error --wave=wave.fst

