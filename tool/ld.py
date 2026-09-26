#!/usr/local/bin/python3

import re, sys, os, pickle, argparse
import yaml
from collections import namedtuple

parser = argparse.ArgumentParser(description = "linker/loader")

parser.add_argument('filename', nargs = '*')
parser.add_argument('-o', '--output', nargs = '?', default = "a.out")
parser.add_argument('-i', '--isa', nargs = '?', default = os.environ["ISA"])
parser.add_argument('-m', '--map', nargs = '?', default = "memory_map.yaml")

args = parser.parse_args()

obj_files = args.filename
out_file = args.output
isa_name = args.isa
map_file = args.map

with open(f"design/vhdl/{isa_name}_ISA.yaml", "r") as f:
    spec = yaml.safe_load(f)

with open(map_file, "r") as f:
    memoryMap = yaml.safe_load(f)

segmentList = memoryMap["segment_list"]
sectionMap = memoryMap["section_mapping"]

sections = {}
segments = {}
labels = {}
references = {}
moduleStart = {}
sectionBase = {}
exports = {}
imports = {}

class LinkError(Exception):
    pass

def iword_to_bytes(iword):
    return bytes([iword & 255, (iword>>8) & 255, (iword>>16) & 255, (iword>>24) & 255])

def bytes_to_iword(b):
    return (b[3]<<24) | (b[2]<<16) | (b[1]<<8) | (b[0]<<0)

def bin(x):
    result = ""
    for i in range(31, -1, -1):
        result += "0" if (x & (1<<i)) == 0 else "1"
    return result

def patch_instruction(section, symOffset, target, bit_offset, num_bits):
    iword = bytes_to_iword(section[symOffset:symOffset+4])
    # print(bin(iword))
    field_mask = (1<<num_bits)-1
    iword = (iword & ~(field_mask<<bit_offset)) | ((target & field_mask)<<bit_offset)
    # print(bin(iword))
    section[symOffset:symOffset+4] = iword_to_bytes(iword)
    return
            
def main():

    #
    # Load all object files
    #
    
    for name in obj_files:
        with open(name, "rb") as f:
            object_code = pickle.load(f)

        moduleStart[name] = {}
        exports[name] = {}
        imports[name] = {}
        
        for sect_name in object_code["sections"]:
            print(f"Loading module {name} section {sect_name}...")

            if not sect_name in sections:
                sections[sect_name] = bytearray()
                
            moduleStart[name][sect_name] = len(sections[sect_name])
            
            sections[sect_name] += object_code["sections"][sect_name]
            
        print(f"Loading module {name} labels...")

        for id in object_code["exports"]:
            print(f"  Exporting symbol {id}")
            exports[name][id] = True

        for id in object_code["imports"]:
            print(f"  Importing symbol {id}")
            imports[name][id] = True

        for key, value in object_code["labels"].items():
            if key in exports[name]:
                symName = key
            else:
                symName = name + ":" + key
                
            labels[symName] = { "module": name, "name": key, "section": value["section"], "offset": +value["offset"]}
            
        references[name] = object_code["references"]

    #
    # Map sections to segments
    #
    
    segment_index = {}
    
    for sect_name in sections:
        segment_name = sectionMap[sect_name]

        if not segment_name in segment_index:
            segment_index[segment_name] = 0
            
        sectionBase[sect_name] = segment_index[segment_name]

        print(f"Mapping section {sect_name} to {segment_name} + {sectionBase[sect_name]}...")

        segment_index[segment_name] += len(sections[sect_name])

    #
    # Resolve references
    #
    
    for module, ref_list in references.items():
        print(f"Resolving module {module}...")
    
        for ref in ref_list:
            symbol = ref["symbol"]

            if symbol in imports[module] or symbol in exports[module]:
                globalName = symbol
            else:
                globalName = module + ":" + symbol

            if globalName in labels:
                label = labels[globalName]
            else:
                raise LinkError(f"Unrecognized symbol '{symbol}' in module {module}")

            targetModule = label["module"]
            targetSect = label["section"]
            targetOffset = label["offset"] + moduleStart[targetModule][targetSect]
        
            symSect = ref["section"]
            symOffset = ref["index"] + moduleStart[module][symSect]
        
            target = segmentList[sectionMap[targetSect]]["base"] + sectionBase[targetSect] + targetOffset
                                     
            if ref["type"] == "i_target":
                target = target>>2
            
            elif ref["type"] == "i_disp":
                target = target - (segmentList[sectionMap[symSect]]["base"] + sectionBase[targetSect] + symOffset)
                target = target>>2

            elif ref["type"] == "disp":
                target = target - (segmentList[sectionMap[symSect]]["base"] + sectionBase[targetSect] + symOffset)

            elif ref["type"] == "value":
                pass
                
            else:
                raise LinkError(f"Unrecognized reference type {ref["type"]}")

            print(f"  {globalName} resolved to {target}")
            patch_instruction(sections[symSect], symOffset, target, ref["bit_offset"], ref["num_bits"])

    #
    # Load sections into segments
    #

    for sect_name in sections:
        segment_name = sectionMap[sect_name]
        segment_index = 0
        
        if not segment_name in segments:
            segments[segment_name] = bytearray()
       
        sectionBase[sect_name] = len(segments[segment_name])

        print(f"Loading section {sect_name} to {segment_name} + {sectionBase[sect_name]}...")

        segments[segment_name] += sections[sect_name]

    #
    # Dump
    #
    
    print("Dumping segment rom0...")

    output_lines = []
    
    with open(f"i_rom.txt", "w") as f:    
        for i in range(0, len(segments["rom0"]), 4):
            output_lines.append(bin(bytes_to_iword(segments["rom0"][i:i+4])))

        f.write("\n".join(output_lines))
main()
