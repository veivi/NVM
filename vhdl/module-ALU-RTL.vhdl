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
  constant Log2WordSize_C : integer := Log2ByteSize_C + Log2BPW_C;
  
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;

  constant Word16Size_C : integer := 2*ByteSize_C;
  
  function Saturate(A : std_logic_vector; W : natural) return std_logic_vector is
    constant Len_C : integer := A'range'high - A'range'low + 1;
    variable MinValue, MaxValue, Temp : signed(A'range);
  begin
    MinValue := (others => '0');
    MinValue(Len_C-1 downto W-1) := (others => '1');
    
    MaxValue := (others => '1');
    MaxValue(Len_C-1 downto W-1) := (others => '0');
    
    Temp := signed(A);
    
    if Temp < MinValue then
      Temp := MinValue;
    elsif Temp > MaxValue then
      Temp := MaxValue;
    end if;
    
    return std_logic_vector(Temp);
  end function;

  function Add(A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
    constant W : integer := A'range'high - A'range'low + 2;
    variable Temp : signed(W-1 downto 0);
  begin
    Temp := resize(signed(A), W) + resize(signed(B), W);
    Temp := signed(Saturate(std_logic_vector(Temp), W-1));
    return std_logic_vector(Temp(W-2 downto 0));
  end function;

  function Negate(A : std_logic_vector) return std_logic_vector is
    constant W : integer := A'range'high - A'range'low + 2;
    variable Temp : std_logic_vector(W-1 downto 0);
  begin
    Temp := std_logic_vector(-resize(signed(A), W));
    Temp := Saturate(Temp, W-1);
    return Temp(W-2 downto 0);
  end function;
  
  function Absolute(A : std_logic_vector) return std_logic_vector is
  begin
    if signed(A) < 0 then
      return Negate(A);
    else
      return A;
    end if;
  end function;
  
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

      when ALUOp_NOR_C =>
        ALUResult <= NOT(A or B);

      when ALUOp_ADD_C =>
        ALUResult <= std_logic_vector(unsigned(A) + unsigned(B));

      when ALUOp_ADD8_C =>
        for I in 0 to 2**Log2BPW_C-1 loop
          ALUResult((I+1)*ByteSize_C-1 downto I*ByteSize_C) <=
            Add(A((I+1)*ByteSize_C-1 downto I*ByteSize_C),
                B((I+1)*ByteSize_C-1 downto I*ByteSize_C));
        end loop;
        
      when ALUOp_ADD16_C =>
        for I in 0 to 2**Log2BPW_C/2-1 loop
          ALUResult((I+1)*Word16Size_C-1 downto I*Word16Size_C) <=
            Add(A((I+1)*Word16Size_C-1 downto I*Word16Size_C),
                B((I+1)*Word16Size_C-1 downto I*Word16Size_C));
        end loop;
        
      when ALUOp_ABS_C =>
        ALUResult <= std_logic_vector(Absolute(A));

      when ALUOp_ABS8_C =>
        for I in 0 to 2**Log2BPW_C-1 loop
          ALUResult((I+1)*ByteSize_C-1 downto I*ByteSize_C) <=
            Absolute(A((I+1)*ByteSize_C-1 downto I*ByteSize_C));
        end loop;
        
      when ALUOp_ABS16_C =>
        for I in 0 to 2**Log2BPW_C/2-1 loop
          ALUResult((I+1)*Word16Size_C-1 downto I*Word16Size_C) <=
            Absolute(A((I+1)*Word16Size_C-1 downto I*Word16Size_C));
        end loop;
        
      when ALUOp_NEG8_C =>
        for I in 0 to 2**Log2BPW_C-1 loop
          ALUResult((I+1)*ByteSize_C-1 downto I*ByteSize_C) <=
            Negate(A((I+1)*ByteSize_C-1 downto I*ByteSize_C));
        end loop;
        
      when ALUOp_NEG16_C =>
        for I in 0 to 2**Log2BPW_C/2-1 loop
          ALUResult((I+1)*Word16Size_C-1 downto I*Word16Size_C) <=
            Negate(A((I+1)*Word16Size_C-1 downto I*Word16Size_C));
        end loop;
        
      when ALUOp_SUB_C =>
        ALUResult <= std_logic_vector(unsigned(A) - unsigned(B));

      when ALUOp_SUB8_C =>
        for I in 0 to 2**Log2BPW_C-1 loop
          ALUResult((I+1)*ByteSize_C-1 downto I*ByteSize_C) <=
            Add(A((I+1)*ByteSize_C-1 downto I*ByteSize_C),
                Negate(B((I+1)*ByteSize_C-1 downto I*ByteSize_C)));
        end loop;
        
      when ALUOp_SUB16_C =>
        for I in 0 to 2**Log2BPW_C/2-1 loop
          ALUResult((I+1)*Word16Size_C-1 downto I*Word16Size_C) <=
            Add(A((I+1)*Word16Size_C-1 downto I*Word16Size_C),
                Negate(B((I+1)*Word16Size_C-1 downto I*Word16Size_C)));
        end loop;
        
      when ALUOp_LSL_C =>
        ALUResult <= std_logic_vector(shift_left(unsigned(A),
                                              to_integer(unsigned(B(Log2WordSize_C-1 downto 0)))));
            
      when ALUOp_LSR_C =>
        ALUResult <= std_logic_vector(shift_right(unsigned(A),
                                              to_integer(unsigned(B(Log2WordSize_C-1 downto 0)))));
            
      when ALUOp_ASR_C =>
        ALUResult <= std_logic_vector(shift_right(signed(A),
                                              to_integer(unsigned(B(Log2WordSize_C-1 downto 0)))));

      when ALUOp_ROTC_C =>
        if signed(B(1 downto 0)) > 0 then
          -- Rotate counter-clockwise
          ALUResult <= Negate(A(WordSize_C/2-1 downto 0)) & A(WordSize_C-1 downto WordSize_C/2);
        elsif signed(B(1 downto 0)) < 0 then
          -- Rotate clockwise
          ALUResult <= A(WordSize_C/2-1 downto 0) & Negate(A(WordSize_C-1 downto WordSize_C/2));
        else
          -- Do nothing
          ALUResult <= A;
        end if;
        
      when ALUOp_ADDRI_C =>
        -- Rotate A counter-clockwise and add to B
        ALUResult <= Add(B(WordSize_C-1 downto WordSize_C/2),
                         Negate(A(WordSize_C/2-1 downto 0)))
                     & Add(B(WordSize_C/2-1 downto 0),
                           A(WordSize_C-1 downto WordSize_C/2));

      when ALUOp_ADDRNI_C =>
        -- Rotate A clockwise and add to B
          ALUResult <= Add(B(WordSize_C-1 downto WordSize_C/2),
                           A(WordSize_C/2-1 downto 0))
                       & Add(B(WordSize_C/2-1 downto 0),
                             Negate(A(WordSize_C-1 downto WordSize_C/2)));
        
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


       
