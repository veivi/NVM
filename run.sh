#!/bin/sh

nvc -e Testbench
nvc -r Testbench --stop-time=5ms --exit-severity=error --wave=wave.fst --dump-arrays=10

