#!/bin/sh

export ISA=NVM101

design/tool/generate.py

nvc -a design/vhdl/package-NVM101Interface.vhdl
nvc -a design/vhdl/package-NVM101Types.vhdl
nvc -a design/vhdl/package-NVM101Types-body.vhdl
nvc -a design/vhdl/module-EIU-RTL.vhdl
nvc -a design/vhdl/module-FCU-RTL.vhdl
nvc -a design/vhdl/module-VRFU-RTL.vhdl
nvc -a design/vhdl/module-VLSU-RTL.vhdl
nvc -a design/vhdl/module-ALU-RTL.vhdl
nvc -a design/vhdl/entity-IDU.vhdl
nvc -a artefact/architecture-IDU-Synthetic.vhdl
nvc -a design/vhdl/module-NVM101-Struct.vhdl
nvc -a design/vhdl/module-VU101-RTL.vhdl
nvc -a design/vhdl/module-VU102-RTL.vhdl
nvc -a design/vhdl/module-LCM-Bhv.vhdl
nvc -a design/vhdl/module-MPM-Bhv.vhdl
nvc -a design/vhdl/module-Testbench-Bhv.vhdl

