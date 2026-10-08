library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use WORK.SignalMath.all;

entity ALU is
  generic(Log2BPW_C : integer);
          
  port(Operation : in ALUOp_T;

       A : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       B : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       SubDatum : out SimpleDatumVector_T(2**Log2BPW_C-1 downto 0);
       Datum : out Datum_T);
end ALU;

architecture RTL of ALU is
  constant Log2WordSize_C : integer := Log2ByteSize_C + Log2BPW_C;
  
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;

  constant Word16Size_C : integer := 2*ByteSize_C;
  
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
        ALUResult <= Absolute(A);

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
        -- A + iB
        ALUResult <= Add(A(WordSize_C-1 downto WordSize_C/2),
                         Negate(B(WordSize_C/2-1 downto 0)))
                     & Add(A(WordSize_C/2-1 downto 0),
                           B(WordSize_C-1 downto WordSize_C/2));

      when ALUOp_ADDRNI_C =>
        -- A - iB
          ALUResult <= Add(A(WordSize_C-1 downto WordSize_C/2),
                           B(WordSize_C/2-1 downto 0))
                       & Add(A(WordSize_C/2-1 downto 0),
                             Negate(B(WordSize_C-1 downto WordSize_C/2)));
        
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
    SubDatum <= (others => DefaultSimpleDatum_C);
    Datum <= DefaultDatum_C;

    for I in 0 to 2**Log2BPW_C-1 loop
      case Operation is
        when ALUOp_CMP8U_C =>
          -- Compare unsigned, 8-bit subword

          if unsigned(CompareA((I+1)*ByteSize_C-1 downto I*ByteSize_C))
            > unsigned(CompareB((I+1)*ByteSize_C-1 downto I*ByteSize_C)) then
            SubDatum(I).GreaterThan <= '1';
          elsif unsigned(CompareA((I+1)*ByteSize_C-1 downto I*ByteSize_C))
            < unsigned(CompareB((I+1)*ByteSize_C-1 downto I*ByteSize_C)) then
            SubDatum(I).LessThan <= '1';
          end if;
  
        when ALUOp_CMP8_C =>
          -- Compare signed, 8-bit subword

          if signed(CompareA((I+1)*ByteSize_C-1 downto I*ByteSize_C))
            > signed(CompareB((I+1)*ByteSize_C-1 downto I*ByteSize_C)) then
            SubDatum(I).GreaterThan <= '1';
          elsif signed(CompareA((I+1)*ByteSize_C-1 downto I*ByteSize_C))
            < signed(CompareB((I+1)*ByteSize_C-1 downto I*ByteSize_C)) then
            SubDatum(I).LessThan <= '1';
          end if;

        when ALUOp_CMP16U_C =>
          -- Compare unsigned, 16-bit subword

          if unsigned(CompareA((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C))
            > unsigned(CompareB((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C)) then
            SubDatum(I).GreaterThan <= '1';
          elsif unsigned(CompareA((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C))
            < unsigned(CompareB((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C)) then
            SubDatum(I).LessThan <= '1';
          end if;

        when ALUOp_CMP16_C =>
          -- Compare signed, 16-bit subword

          if signed(CompareA((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C))
            > signed(CompareB((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C)) then
            SubDatum(I).GreaterThan <= '1';
          elsif signed(CompareA((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C))
            < signed(CompareB((I/2+1)*Word16Size_C-1 downto I/2*Word16Size_C)) then
            SubDatum(I).LessThan <= '1';
          end if;

        when ALUOp_CMPU_C =>
          -- Explicit compare unsigned
      
          if unsigned(CompareA) > unsigned(CompareB) then
            Subdatum(I).GreaterThan <= '1';
            Datum.Compare.GreaterThan <= '1';
          elsif unsigned(CompareA) < unsigned(CompareB) then
            SubDatum(I).LessThan <= '1';
            Datum.Compare.LessThan <= '1';
          end if;

        when others =>
          -- Explicit or implicit compare signed
      
          if signed(CompareA) > signed(CompareB) then
            Subdatum(I).GreaterThan <= '1';
            Datum.Compare.GreaterThan <= '1';
          elsif signed(CompareA) < signed(CompareB) then
            SubDatum(I).LessThan <= '1';
            Datum.Compare.LessThan <= '1';
          end if;
      end case;
    end loop;
  end process;
  
  Result <= ALUResult;
end RTL;


       
