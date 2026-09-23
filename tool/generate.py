#!/usr/local/bin/python3

import sys, os

# filename = sys.argv[1]
arch = os.environ["ISA"]

# generate_header.py
import yaml

# Load the YAML specification
with open(f"design/vhdl/{arch}_ISA.yaml", "r") as f:
    spec = yaml.safe_load(f)

arch_name = spec["architecture"].upper()
iword_size = spec["iword_size_bits"]
formats = spec["instruction_formats"]
categories = spec["instruction_categories"]
opcodes = spec["instruction_set"]

# Build the header content
header_lines = [
    f"#ifndef {arch_name}_INTERFACE_H",
    f"#define {arch_name}_INTERFACE_H",
    "",
    "/* Automatically generated. Do not modify. */",
    ""
]

def instruction_field(format, field) -> (int, int):
    value = iword_size
    for f in format:
        value = value - format[f]
        if f == field:
            return(value, format[f])
    return(null)

# Generate register definitions
header_lines.append("/* Register Definitions */")
#for reg in spec["registers"]:
#    print(reg) # header_lines.append(f"#define REG_{reg["name"]} {reg["address"]}")
header_lines.append("")

# Format definitions

header_lines.extend(["/* Format Definitions */", ""])

for f in formats:
    format = formats[f]
    line = f"#define {arch_name}_FORMAT_{f.upper()}("

    first = True
    
    for field in format:
        if not first:
            line += ", "
        line += f"{field}"
        first = False

    line += ") \\\n   ( "

    first = True
    
    for field in format:
        if not first:
            line += " \\\n   | "
        (offset, length) = instruction_field(format, field)
        line += f"(({field} & ((1UL<<{length})-1))<<{offset})"
        first = False

    line += " )"
    
    header_lines.append(line)
    
# Generate opcode definitions

header_lines.extend(["", "/* Opcode Definitions */", ""])

for op in opcodes:
    opcode = opcodes[op]
    header_lines.append(f"#define {arch_name}_OPCODE_{op} {opcode["opcode"]} /* {opcode['behaviour']} */")

header_lines.extend(["", f"#endif /* {arch_name}_ISA_H */"])

# Instruction word generator macros

header_lines.extend(["", "/* Instruction Generators */", ""])

for op in opcodes:
    opcode = opcodes[op]

    category = categories[opcode["category"]]
    
    format = formats[category["format"]]

    line = f"#define {arch_name}_ENCODE_{op}(";
    first = True
    
    for field in format:
        if field == "opcode":
            continue
            
        if not first:
            line += ", "
            
        line += f"{field}"
        first = False

    line += f") \\\n  {arch_name}_FORMAT_{category["format"].upper()}("
    line += f"{arch_name}_OPCODE_{op}";
    
    for field in format:
        if field == "opcode":
            continue
            
        line += ", "
            
        line += f"{field}"
        
    line += ")"
    
    header_lines.append(line)

header_lines.extend(["", f"#endif /* {arch_name}_INTERFACE_H */"])

# Write to the C header file
with open(f"artefact/{arch}_Interface.h", "w") as f:
    f.write("\n".join(header_lines))

print("Header file generated successfully.")

# Build the instruction decoder

decoder_lines = [
    "library IEEE;",
    "use IEEE.std_logic_1164.all;",
    "use IEEE.numeric_std.all;",
    "use WORK.NVM101Types.all;",
    "",
    "architecture Synthetic of IDU is",
    "  function RegIndex(Index : std_logic_vector) return RegIndex_T is",
    "  begin",
    "    return to_integer(unsigned(Index));",
    "  end function;",
     "  function CondIndex(Index : std_logic_vector) return CondRegIndex_T is",
    "  begin",
    "    return to_integer(unsigned(Index));",
    "  end function;",
    "begin",
    "  Decoder_P : process(I_Code)",
    "  begin",
    "    --",
    "    -- Control word default",
    "    --",
    "",
    "    ControlWord <= DefaultControlWord_C;",
    ""
]

# Find out the minimum opcode size for scaling of the prefix

min_prefix = iword_size

for f in formats:
    (offset, size) = instruction_field(formats[f], "opcode")
    
    if size < min_prefix:
        min_prefix = size

print(f"Minimal prefix is {min_prefix} bits")

first = True
    
for op in opcodes:
    print(f"Generating decode for {op}...")
    
    opcode = opcodes[op]

    category = categories[opcode["category"]]
    
    format = formats[category["format"]]

    (offset, length) = instruction_field(format, "opcode")

    decoder_lines.append( "")
    decoder_lines.append( "    --")
    decoder_lines.append(f"    -- Mnemonic {op}")
    decoder_lines.append( "    --")
    decoder_lines.append( "")
    
    if first:
        line = "    if "
    else:
        line = "    elsif "
        
    line += f"to_integer(unsigned(I_Code({offset+length-1} downto {offset}))) = {category["prefix"]<<(length - min_prefix)} + {opcode["opcode"]} then"
    decoder_lines.append(line)
    
    if "operation" in opcode:
        decoder_lines.append(f"      ControlWord.{category["unit"]}_Operation <= {opcode["operation"]};")
    if "mode" in category:
        decoder_lines.append(f"      ControlWord.{category["unit"]}_Mode <= {category["mode"]};")
    if "imm-unsigned" in category:
        (offset, length) = instruction_field(format, category["imm-unsigned"])
        decoder_lines.append(f"      Imm_Data <= std_logic_vector(resize(unsigned(I_Code({offset+length-1} downto {offset})), ByteSize_C*2**Log2BPW_C));")
    if "imm-high" in category:
        (offset, length) = instruction_field(format, category["imm-high"])
        decoder_lines.append(f"      Imm_Data(ByteSize_C*2**Log2BPW_C-1 downto ByteSize_C*2**Log2BPW_C - {length})  <= I_Code({offset+length-1} downto {offset});")
    if "imm-signed" in category:
        (offset, length) = instruction_field(format, category["imm-signed"])
        decoder_lines.append(f"      Imm_Data <= std_logic_vector(resize(signed(I_Code({offset+length-1} downto {offset})), ByteSize_C*2**Log2BPW_C));")
    if "register-read-a" in category:
        (offset, length) = instruction_field(format, category["register-read-a"])
        decoder_lines.append("      ControlWord.RF_RA_Active <= '1';")
        decoder_lines.append(f"      ControlWord.RF_RA_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "register-read-b" in category:
        (offset, length) = instruction_field(format, category["register-read-b"])
        decoder_lines.append("      ControlWord.RF_RB_Active <= '1';")
        decoder_lines.append(f"      ControlWord.RF_RB_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "register-read-c" in category:
        (offset, length) = instruction_field(format, category["register-read-c"])
        decoder_lines.append("      ControlWord.RF_RC_Active <= '1';")
        decoder_lines.append(f"      ControlWord.RF_RC_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "register-write" in category:
        (offset, length) = instruction_field(format, category["register-write"])
        decoder_lines.append("      ControlWord.RF_W_Active <= '1';")
        decoder_lines.append(f"      ControlWord.RF_W_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-read-a" in category:
        (offset, length) = instruction_field(format, category["vector-read-a"])
        decoder_lines.append("      ControlWord.VRF_RA_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VRF_RA_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-read-b" in category:
        (offset, length) = instruction_field(format, category["vector-read-b"])
        decoder_lines.append("      ControlWord.VRF_RB_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VRF_RB_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-read-c" in category:
        (offset, length) = instruction_field(format, category["vector-read-c"])
        decoder_lines.append("      ControlWord.VRF_RC_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VRF_RC_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-write" in category:
        (offset, length) = instruction_field(format, category["vector-write"])
        decoder_lines.append("      ControlWord.VRF_W_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VRF_W_Index <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    if "condition-read" in category:
        (offset, length) = instruction_field(format, category["condition-read"])
        decoder_lines.append("      ControlWord.CR_Read_Active <= '1';")
        decoder_lines.append(f"      ControlWord.CR_Read_Index <= CondIndex(I_Code({offset+length-1} downto {offset}));")
    if "condition-write" in category:
        (offset, length) = instruction_field(format, category["condition-write"])
        decoder_lines.append("      ControlWord.CR_Write_Active <= '1';")
        decoder_lines.append(f"      ControlWord.CR_Write_Index <= CondIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-condition-read" in category:
        (offset, length) = instruction_field(format, category["vector-condition-read"])
        decoder_lines.append("      ControlWord.VCR_Read_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VCR_Read_Index <= CondIndex(I_Code({offset+length-1} downto {offset}));")
    if "vector-condition-write" in category:
        (offset, length) = instruction_field(format, category["vector-condition-write"])
        decoder_lines.append("      ControlWord.VCR_Write_Active <= '1';")
        decoder_lines.append(f"      ControlWord.VCR_Write_Index <= CondIndex(I_Code({offset+length-1} downto {offset}));")
    if "sub-operation" in category:
        (offset, length) = instruction_field(format, category["sub-operation"])
        decoder_lines.append(f"      ControlWord.{category["unit"]}_Active <= '1';")
        decoder_lines.append(f"      ControlWord.{category["unit"]}_Operation <= to_integer(unsigned(I_Code({offset+length-1} downto {offset})));")
    if "ext-result" in category:
        (offset, length) = instruction_field(format, category["ext-result"])
        decoder_lines.append(f"      ControlWord.{category["unit"]}_Result <= RegIndex(I_Code({offset+length-1} downto {offset}));")
    
    first = False

    
decoder_lines.extend(["    end if;",
                      "  end process;",
                      "end Synthetic;"])

# Write to the decoder file
with open("artefact/architecture-IDU-Synthetic.vhdl", "w") as f:
    f.write("\n".join(decoder_lines))

print("Decoder file generated successfully.")



