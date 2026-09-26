#!/bin/sh

nvc -e Testbench
nvc -r Testbench --stop-time=1000us --wave=wave.fst --dump-arrays=10

