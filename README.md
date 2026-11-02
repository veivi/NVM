NVM101 is an exercise in SIMD processor design. Old-fashioned handwritten VHDL, any vibes are in your head. This thing was created during an approximately two-week period of coding. More work would be needed for verification and physical design.
The instruction set (as well as encoding) is defined in vhdl/NVM101_ISA.yaml. It is incomplete and unoptimized, pretty much only contains stuff I needed for my FFT implementation which I used as a benchmark.
No exception/multithreading support for the time being, if this thing finds a use that pays my mortgage
then it will be added. :)
