# What is this?
NVM101 is an exercise in SIMD processor design. Old-fashioned handwritten VHDL, any vibes are in your head. This thing was created during an approximately two-week period of coding. The design is basically RTL but not tested for synthesis as I lack the tools, some behavioural bits mixed in for quick and dirty testing. More work would be needed for verification and physical design.

# Instruction set
The instruction set (as well as encoding) is defined in vhdl/NVM101_ISA.yaml. It is incomplete and unoptimized, pretty much only contains stuff I needed for my FFT implementation which I used as a benchmark.

# What's missing?
No exception/multithreading support for the time being, if this thing finds a use that pays my mortgage then it will be added. :)
