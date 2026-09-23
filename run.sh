#!/bin/sh

nvc -e Testbench
nvc -r Testbench --stop-time=100us --wave=wave.fst --dump-arrays=10

