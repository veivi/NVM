#!/bin/sh

export ISA=NVM101

design/tool/generate.py

if [ $? -ne 0 ]; then
    echo "generate.py failed"
    exit 10
fi

source="design/vhdl/package-NVM101Interface.vhdl design/vhdl/package-SignalMath.vhdl design/vhdl/package-SignalMath-body.vhdl design/vhdl/package-NVM101Types.vhdl design/vhdl/package-NVM101Types-body.vhdl design/vhdl/module-EIU-RTL.vhdl design/vhdl/module-FCU-RTL.vhdl design/vhdl/module-RFU-RTL.vhdl design/vhdl/module-LSU-RTL.vhdl design/vhdl/module-ALU-RTL.vhdl design/vhdl/entity-IDU.vhdl artefact/architecture-IDU-Synthetic.vhdl design/vhdl/module-NVM101-Struct.vhdl design/vhdl/module-VU101-RTL.vhdl design/vhdl/module-VU102-RTL.vhdl design/vhdl/module-VU103-RTL.vhdl design/vhdl/module-LCM-Bhv.vhdl design/vhdl/module-MPM-Bhv.vhdl design/vhdl/module-Testbench-Bhv.vhdl design/vhdl/module-FP16Testbench-Bhv.vhdl"

for i in $source; do
    echo "Analyzing $i..."
    nvc -a $i
#    ghdl analyze --std=08 $i 
    if [ $? -ne 0 ]; then
	echo "Analysis of $i failed."
	exit 10
    fi
done

