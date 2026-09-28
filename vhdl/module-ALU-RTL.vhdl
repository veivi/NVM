library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity ALU is
  generic(Log2BPW_C : integer);
          
  port(Operation : in ALUOp_T;

       A : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       B : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Datum : out Datum_T);
end ALU;

architecture RTL of ALU is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  signal ALUResult, CompareA, CompareB : std_logic_vector(WordSize_C-1 downto 0);
begin
  --
  -- Logic implementation
  --
  
  ALU_P : process(Operation, A, B)
  begin
    -- Default result
    
    ALUResult <= (others => '0');
    
    case Operation is
      when ALUOp_OR_C =>
        ALUResult <= A or B;

      when ALUOp_AND_C =>
        ALUResult <= A and B;

      when ALUOp_XOR_C =>
        ALUResult <= A xor B;

      when ALUOp_ADD_C =>
        ALUResult <= std_logic_vector(unsigned(A) + unsigned(B));

      when ALUOp_SUB_C =>
        ALUResult <= std_logic_vector(unsigned(A) - unsigned(B));

      when ALUOp_LSL_C =>
        ALUResult <= std_logic_vector(shift_left(unsigned(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            
      when ALUOp_LSR_C =>
        ALUResult <= std_logic_vector(shift_right(unsigned(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            
      when ALUOp_ASR_C =>
        ALUResult <= std_logic_vector(shift_right(signed(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            
      when others =>
        null;
    end case; 
  end process;

  --
  -- Comparator operand select
  --
  
  CompareInput_P : process(Operation, A, B, ALUResult)
  begin
    if Operation = ALUOp_CMP_C or Operation = ALUOp_CMPU_C then
      -- Explicit comparison
      CompareA <= A;
      CompareB <= B;
    else
      -- Implicit comparison of result and zero
      CompareA <= ALUResult;
      CompareB <= (others => '0');
    end if;
  end process;

  --
  -- Comparator
  --
  
  Compare_P : process(Operation, CompareA, CompareB)
  begin
    Datum <= DefaultDatum_C;
    
    if Operation = ALUOp_CMPU_C then
      -- Explicit compare unsigned
      
      if unsigned(CompareA) > unsigned(CompareB) then
        Datum.GreaterThan <= '1';
      elsif unsigned(CompareA) < unsigned(CompareB) then
        Datum.LessThan <= '1';
      end if;
    else 
      -- Explicit or implicit compare signed
      
      if signed(CompareA) > signed(CompareB) then
        Datum.GreaterThan <= '1';
      elsif signed(CompareA) < signed(CompareB) then
        Datum.LessThan <= '1';
      end if;
    end if;
  end process;

  Result <= ALUResult;
end RTL;


       
