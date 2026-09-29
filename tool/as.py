#!/usr/local/bin/python3

import re, sys, os, pickle, argparse
import yaml
from collections import namedtuple

parser = argparse.ArgumentParser(description = "Assembler")

parser.add_argument('filename')
parser.add_argument('-o', '--output', nargs = '?')
parser.add_argument('-i', '--isa', nargs = '?', default = os.environ["ISA"])

args = parser.parse_args()

filename = args.filename
out_file = args.output
isa_name = args.isa

filename_body, filename_ext = os.path.splitext(filename)

if out_file == None:
    out_file = f"{os.path.basename(filename_body)}.obj"

filename_pp = f"artefact/{os.path.basename(filename_body)}.pp"

with open(f"design/vhdl/{isa_name}_ISA.yaml", "r") as f:
    spec = yaml.safe_load(f)
        
iword_size = spec["iword_size_bits"]
formats = spec["instruction_formats"]
categories = spec["instruction_categories"]
opcodes = spec["instruction_set"]


Token = namedtuple("Token", ["type", "value"])

token_spec = [
    ("COMMENT",   r"[#/;].*"),
#    ("COMMENT2",   r"#.*"),
#    ("COMMENT3",   r"#.*"),
    ("DIRECTIVE", r"\.\w+"),
    ("LABEL",     r"^\w+:"),
    ("STRING",    r'"[^"]*"'),
    ("REGISTER",  r"%\d+"),
    ("SCALAR",    r"s\d+"),
    ("VECTOR",    r"v\d+"),
    ("CREGISTER", r"[cC]\d+"),
    ("VCREGISTER", r"vc\d+"),
    ("UNIT",      r"[uU]\d+"),
    ("HEX",       r"-?0x[\da-fA-F]+"),
    ("DEC",       r"-?\d+"),
    ("IDENT",     r"[A-Za-z_]\w*"),
    ("COMMA",     r","),
    ("PLUS",      r"\+"),
    ("BRACKET_L", r"\["),
    ("BRACKET_R", r"\]"),
    ("NEWLINE",   r"\n"),
    ("WS",        r"[ \t]+"),
    ("MISMATCH",  r".")
]

tok_regex = "|".join(f"(?P<{name}>{pattern})" for name, pattern in token_spec)

def tokenize(text):
    for m in re.finditer(tok_regex, text, re.MULTILINE):
        kind = m.lastgroup
        value = m.group()
        if kind in ("WS", "COMMENT", "COMMENT2"):
            continue
        elif kind == "MISMATCH":
            raise SyntaxError(f"Unexpected character {value!r}")
        yield Token(kind, value)
    yield Token("EOF", None)

class LabelDef:
    def __init__(self, name):
        self.name = name
    def __repr__(self):
        return f"LabelDef({self.name})"

class Directive:
    def __init__(self, name, args):
        self.name = name
        self.args = args
    def __repr__(self):
        return f"Directive({self.name}, {self.args})"

class Instruction:
    def __init__(self, mnemonic, operands):
        self.mnemonic = mnemonic
        self.operands = operands
    def __repr__(self):
        return f"Instruction({self.mnemonic}, {self.operands})"

class Register:
    def __init__(self, num):
        self.index = num
    def __repr__(self):
        return f"S({self.index})"

class Address:
    def __init__(self, num, displacement):
        self.index = num
        self.displacement = displacement
    def __repr__(self):
        return f"[S{self.index} + {self.displacement}]"

class ConditionRegister:
    def __init__(self, num):
        self.index = num
    def __repr__(self):
        return f"C({self.index})"

class VectorRegister:
    def __init__(self, num):
        self.index = num
    def __repr__(self):
        return f"V({self.index})"

class VectorConditionRegister:
    def __init__(self, num):
        self.index = num
    def __repr__(self):
        return f"VC({self.index})"

class Unit:
    def __init__(self, num):
        self.index = num
    def __repr__(self):
        return f"U({self.index})"

class Immediate:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return f"Imm({self.value})"

class Multiple:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return f"Multiple({self.value})"

class Ident:
    def __init__(self, name):
        self.name = name
    def __repr__(self):
        return f"Ident({self.name})"

class StringLit:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return self.value

# --- Parser ---

class ParseError(Exception):
    pass

class Parser:
    def __init__(self, tokens):
        self.tokens = list(tokens)
        self.pos = 0

    # -- token stream helpers --

    def peek(self):
        return self.tokens[self.pos]

    def advance(self):
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def check(self, *types):
        return self.peek().type in types

    def expect(self, type_):
        tok = self.peek()
        if tok.type != type_:
            raise ParseError(f"Expected {type_}, got {tok.type} ({tok.value!r})")
        return self.advance()

    def skip_newlines(self):
        while self.check("NEWLINE"):
            self.advance()

    # -- grammar rules --

    def parse_program(self):
        """program := (line)* EOF"""
        statements = []
        self.skip_newlines()
        while not self.check("EOF"):
            stmt = self.parse_line()
            if stmt is not None:
                statements.append(stmt)
            self.skip_newlines()
        return statements

    def parse_line(self):
        """line := LABEL? (directive | instruction)?"""
        label = None
        if self.check("LABEL"):
            tok = self.advance()
            label = LabelDef(tok.value.rstrip(":"))
            # A label can stand alone on its line, or be followed by
            # a directive/instruction on the same line.
            if self.check("NEWLINE", "EOF"):
                return label

        if self.check("DIRECTIVE"):
            stmt = self.parse_directive()
        elif self.check("IDENT"):
            stmt = self.parse_instruction()
        elif self.check("NEWLINE", "EOF"):
            return label  # blank/label-only line
        else:
            tok = self.peek()
            raise ParseError(f"Unexpected token {tok.type} ({tok.value!r})")

        if label is not None:
            return (label, stmt)
        return stmt

    def parse_directive(self):
        """directive := DIRECTIVE operand_list?"""
        tok = self.advance()  # DIRECTIVE
        args = []
        if not self.check("NEWLINE", "EOF"):
            args = self.parse_operand_list()
        return Directive(tok.value[1:], args)

    def parse_instruction(self):
        """instruction := IDENT operand_list?"""
        tok = self.advance()  # IDENT (mnemonic)
        operands = []
        if not self.check("NEWLINE", "EOF"):
            operands = self.parse_operand_list()
        return Instruction(tok.value, operands)

    def parse_operand_list(self):
        """operand_list := operand (COMMA operand)*"""
        operands = [self.parse_operand()]
        while type(operands[-1]) == Directive or self.check("COMMA") or self.check("PLUS"):
            self.advance()
            operands.append(self.parse_operand())
        return operands

    def parse_operand(self):
        """operand := REGISTER | IMMEDIATE | STRING | IDENT"""
        tok = self.peek()
        if tok.type == "REGISTER":
            self.advance()
            return Register(int(tok.value[1:]))
        elif tok.type == "SCALAR":
            self.advance()
            return Register(int(tok.value[1:]))
        elif tok.type == "VECTOR":
            self.advance()
            return VectorRegister(int(tok.value[1:]))
        elif tok.type == "CREGISTER":
            self.advance()
            return ConditionRegister(int(tok.value[1:]))
        elif tok.type == "VCREGISTER":
            self.advance()
            return VectorConditionRegister(int(tok.value[2:]))
        elif tok.type == "UNIT":
            self.advance()
            return Unit(int(tok.value[1:]))
        elif tok.type in ("DEC", "HEX"):
            self.advance()
            return Immediate(int(tok.value, 0))
        elif tok.type == "STRING":
            self.advance()
            return StringLit(tok.value[1:-1])  # strip quotes
        elif tok.type == "IDENT":
            self.advance()
            return Ident(tok.value)
            return Multiple(int(tok.value[1:]))
        elif tok.type == "BRACKET_L":
            self.advance()
            
            if self.check("REGISTER"):
                tok = self.peek()
                base = Register(int(tok.value[1:]))
                self.advance()

                if self.check("PLUS"):
                    self.advance()
                elif self.check("BRACKET_R"):
                    self.advance()
                    return Address(base, 0)
                else:
                    raise ParseError("Expected closing bracket")
                    
            else:
                raise ParseError(f"Expected register, got {tok.type} ({tok.value!r})")
        else:
            raise ParseError(f"Expected operand, got {tok.type} ({tok.value!r})")

def instruction_field(format, field):
    value = iword_size
    for f in format:
        value = value - format[f]
        if f == field:
            return(value, format[f])
    return(null)

def iword_to_bytes(iword):
    return bytes([iword & 255, (iword>>8) & 255, (iword>>16) & 255, (iword>>24) & 255])

def bin(s):
    return str(s) if s<=1 else bin(s>>1) + str(s&1)

def assemble(mnemonic, params):
    if mnemonic == "NOP":
        return (iword_to_bytes(0), None)

    # print(f"Mnemonic {mnemonic}")

    multiple = 1
    log2multiple = 0
    
    if mnemonic[-1].isdigit():
        multiple = ord(mnemonic[-1]) - ord('0')
        mnemonic = mnemonic[:-1]

        while multiple > 1:
            log2multiple = log2multiple + 1
            multiple /= 2

        print(f"Multiple {multiple} (log2 {log2multiple})")
    
    ispec = opcodes[mnemonic]

    catName = ispec["category"]
    delta = 0
    
    if "variant-name" in ispec:
        if type(params[-1]) in (Immediate, Ident):
            # Must be an immediate variant
            
            varName = ispec["variant-name"]
            if varName != "imm":
                raise ParseError("Instruction {mnemonic} has no variant-imm")
            
            catName += "_" + varName
            delta = ispec["variant-delta"]
            # print(f"  {mnemonic} with imm operand, delta = {delta}")
    
    category = categories[catName]    
    format = formats[category["format"]]
    formal_args = category["operands"]

    (opcode_offset, opcode_size) = instruction_field(format, "opcode")    
    iword = ((category["prefix"]<<(opcode_size - min_prefix)) + ispec["opcode"] + delta) << opcode_offset
    ref = None

    if "multiple-span" in category:
        (span_offset, span_size) = instruction_field(format, "span")
        iword |= log2multiple<<span_offset;
        
    param_index = 0

    for arg in formal_args:
#        print(f"Formal operand {arg}")
        (offset, size) = instruction_field(format, arg)
        
        if arg in ("rd", "rs", "rs1", "rs2"):
            op = params[param_index]
            
            if type(op) == Register:
                iword |= op.index << offset
            else:
                raise ParseError(f"{mnemonic} rs/rs1/rs2/rd expects a scalar register")
            
        elif arg in ("vd", "vs", "vs1", "vs2"):
            op = params[param_index]
            
            if type(op) == VectorRegister:
                iword |= op.index << offset
            else:
                raise ParseError(f"{mnemonic} vd/vs/vs1/vs2 expects a vector register")
            
        elif arg == "cr":
            op = params[param_index]
            
            if type(op) == ConditionRegister:
                iword |= op.index << offset
            else:
                raise ParseError(f"{mnemonic} cr expects a condition register")
            
        elif arg == "vcr":
            op = params[param_index]
            
            if type(op) == VectorConditionRegister:
                iword |= op.index << offset
            else:
                raise ParseError(f"{mnemonic} vcr expects a vector condition register")
            
        elif arg == "unit":
            op = params[param_index]
            
            if type(op) == Unit:
                iword |= op.index << offset
            else:
                raise ParseError(f"{mnemonic} unit id expected")
            
        elif arg == "i_disp":
            op = params[param_index]
            
            if type(op) == Immediate:
                iword |= (op.value & ((1<<size) - 1)) << offset

            elif type(op) == Ident:
                ref = { "type": arg, "symbol": op.name, "bit_offset": offset, "num_bits": size }
                
            else:
                raise ParseError(f"{mnemonic} disp expects an identifier")
                
        elif arg == "i_target":
            op = params[param_index]
            
            if type(op) == Ident:
                ref = { "type": arg, "symbol": op.name, "bit_offset": offset, "num_bits": size }
                
            else:
                raise ParseError(f"{mnemonic} target expects an identifier")
                
        elif arg in ("value", "index", "disp", "op", "scale", "stride", "subop"):
            op = params[param_index]
            
            if type(op) == Immediate:
                iword |= (op.value & ((1<<size) - 1)) << offset

            elif type(op) == Ident:
                # print(f"ref {op.name}")
                ref = { "type": arg, "symbol": op.name, "bit_offset": offset, "num_bits": size }
                
            else:
                raise ParseError(f"{mnemonic} immediate expected for a value/index/offset")
                
        else:
            raise ParseError(f"Unidentified field '{arg}' in instr '{mnemonic}' format {format}")        
            
        param_index = param_index + 1

    # print(bin(iword))
    
    return (iword_to_bytes(iword), ref)

def main():
    os.system(f"cpp -Idesign/test -DV=8 -DLOG2V=3 {filename} >{filename_pp}")
    file = open(filename_pp)

    print(f"Assembling {filename}...")
    ast = Parser(tokenize(file.read())).parse_program()

    sections = dict()
    labels = dict()
    references = []
    exportList = []
    importList = []

    for node in ast:
        if type(node) == Directive:
            if node.name == "section":
                sectionName = node.args[0].value
                sections[sectionName] = bytearray()
                
            elif node.name == "export":
                exportList.append(node.args[0].value)
                
            elif node.name == "import":
                importList.append(node.args[0].value)
                
            elif node.name == "align":
                n = len(sections[sectionName]) % node.args[0].value
                if n > 0:
                    sections[sectionName] += bytes(node.args[0].value - n)
                
            elif node.name == "string":
                sections[sectionName] += node.args[0].value.encode("utf-8")
                
            elif node.name == "byte":
                sections[sectionName] += bytearray(node.args[0].value)
                
            elif node.name == "short":
                sections[sectionName] += bytearray(2*node.args[0].value)
                
            elif node.name == "long":
                sections[sectionName] += bytearray(4*node.args[0].value)
                
            elif node.name == "word":
                sections[sectionName] += bytearray(8*node.args[0].value)

            else:
                raise ParseError(f"Unrecognized directive {node.name}")
                
        elif type(node) == LabelDef:
            labels[node.name] = { "section": sectionName, "offset": len(sections[sectionName]) }
            
        elif type(node) == Instruction:
            (iword, ref) = assemble(node.mnemonic.upper(), node.operands)
            
            if ref != None:
                ref["section"] = sectionName
                ref["index"] = len(sections[sectionName])
                references.append(ref)

            sections[sectionName] += iword

    output = {
        "sections": sections,
        "labels": labels,
        "references": references,
        "exports": exportList,
        "imports": importList
    }
    
    with open(out_file, 'wb') as outfile:
        pickle.dump(output, outfile)
    
# Find out the minimum opcode size for scaling of the prefix

min_prefix = iword_size

for f in formats:
    (offset, size) = instruction_field(formats[f], "opcode")
    
    if size < min_prefix:
        min_prefix = size

main()
