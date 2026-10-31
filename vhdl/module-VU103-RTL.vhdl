-------------------------------------------------------------------------------
-- Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
-- 
-- PROPRIETARY AND CONFIDENTIAL.
-- Unauthorized copying, modification, or distribution of this file, 
-- via any medium, is strictly prohibited.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use WORK.SignalMath.all;
-- use std.textio.all;

entity VU103 is
  generic(Log2BPW_C : integer;
          Log2VecSize_C : integer;
          Precision_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Vector Unit Command

       AVU_C_Present : in  std_logic;
       AVU_C_Accept : out std_logic;
       AVU_C_Operation : in std_logic_vector(ExtOpSize_C-1 downto 0);
       AVU_C_Tag : in std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_C_Respond : in std_logic;
       AVU_C_OperandA : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       AVU_C_OperandB : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

       -- Vector Unit Result

       AVU_R_Present : out std_logic;
       AVU_R_Tag : out std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_R_Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0));
end VU103;

architecture RTL of VU103 is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;

  subtype Word_T is std_logic_vector(WordSize_C-1 downto 0);

  type WordArray_T is array (natural range <>) of Word_T;
  
  --
  -- Real/Imaginary part representation
  --
  
  constant ScalarSize_C : integer := WordSize_C/2;
  
  subtype Scalar_T is std_logic_vector(ScalarSize_C-1 downto 0);

  function RealPart(A : Word_T) return Scalar_T is
  begin
    return A(WordSize_C-1 downto ScalarSize_C);
  end function;
  
  function ImagPart(A : Word_T) return Scalar_T is
  begin
    return A(ScalarSize_C-1 downto 0);
  end function;

  function Complex(RP : Scalar_T; IP : Scalar_T) return Word_T is
  begin
    return RP & IP;
  end function;

  -- Non-normalized result of multiplication or addition
  
  constant IntPrec_C : integer := Precision_C/4;

  subtype DenormResult_T is GenericFP_T(Mantissa(IntPrec_C+Precision_C-1 downto 0));
  
  type PartialComplexMultiplyResult_T is record
    RealARealB : DenormResult_T;
    ImagAImagB : DenormResult_T;
    RealAImagB : DenormResult_T;
    ImagARealB : DenormResult_T;
  end record;

  type DenormComplexResult_T is record
    Real : DenormResult_T;
    Imag : DenormResult_T;
  end record;

  type PartialMultiplyResultArray_T is array (natural range <>) of PartialComplexMultiplyResult_T;

  type DenormResultArray_T is array (natural range <>) of DenormComplexResult_T;
  
  signal PartialMultiplyResult : PartialMultiplyResultArray_T(0 to 2**Log2VecSize_C-1);
  signal DenormResult : DenormResultArray_T(0 to 2**Log2VecSize_C-1);
  signal PartialValid, DenormValid : std_logic;
  signal PartialTag, DenormTag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal PartialRespond, DenormRespond : std_logic;
begin
  --
  -- Multiplication stage
  --

  Multiplier_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        PartialValid <= '0';

      elsif AVU_C_Present = '1' and to_integer(unsigned(AVU_C_Operation(2 downto 0))) = 0 then
        for I in 0 to 2**Log2VecSize_C-1 loop
          A := AVU_C_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C);
          B := AVU_C_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C);

          PartialMultiplyResult(I) <= ( FP16MultiplyDenorm(RealPart(A), RealPart(B), IntPrec_C),
                                        FP16MultiplyDenorm(ImagPart(A), ImagPart(B), IntPrec_C),
                                        FP16MultiplyDenorm(RealPart(A), ImagPart(B), IntPrec_C),
                                        FP16MultiplyDenorm(ImagPart(A), RealPart(B), IntPrec_C) );

        end loop;

        PartialValid <= '1';
        PartialRespond <= AVU_C_Respond;
        PartialTag <= AVU_C_Tag;
      else
        PartialValid <= '0';
      end if;
    end if;
  end process;
  
  AVU_C_Accept <=
    -- We can always issue a multiplication
    '1' when to_integer(unsigned(AVU_C_Operation(2 downto 0))) = 0
    -- We can only issue if there's no conflicting multiply going on
    else not PartialValid;
  
  --
  -- Adder stage
  --
  
  Adder_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        DenormValid <= '0';

      else
        if PartialValid = '1' then
          -- Complex multiply in the pipeline
        
          for I in 0 to 2**Log2VecSize_C-1 loop
            DenormResult(I) <=
              ( SubtractGenericFP(PartialMultiplyResult(I).RealARealB,
                                  PartialMultiplyResult(I).ImagAImagB, 0),
                AddGenericFP(PartialMultiplyResult(I).RealAImagB,
                             PartialMultiplyResult(I).ImagARealB, 0) );
          end loop;   

          DenormValid <= '1';
          DenormTag <= PartialTag;
          DenormRespond <= PartialRespond;
            
        elsif AVU_C_Present = '1' and to_integer(unsigned(AVU_C_Operation(2 downto 0))) /= 0 then
            -- Complex add/sub/etc being started

          for I in 0 to 2**Log2VecSize_C-1 loop
            A := AVU_C_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C);
            B := AVU_C_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C);
          
            case to_integer(unsigned(AVU_C_Operation(2 downto 0))) is
              when 1 =>      
                -- A + B
            
                DenormResult(I) <= ( FP16AddDenorm(RealPart(A), RealPart(B), IntPrec_C),
                                        FP16AddDenorm(ImagPart(A), ImagPart(B), IntPrec_C) );
              
              when 2 =>      
                -- A - B
            
                DenormResult(I) <= ( FP16SubtractDenorm(RealPart(A), RealPart(B), IntPrec_C),
                                        FP16SubtractDenorm(ImagPart(A), ImagPart(B), IntPrec_C) );

              when 3 =>      
                -- A + iB
            
                DenormResult(I) <= ( FP16SubtractDenorm(RealPart(A), ImagPart(B), IntPrec_C),
                                        FP16AddDenorm(ImagPart(A), RealPart(B), IntPrec_C) );
              
              when 4 =>      
                -- A - iB
            
                DenormResult(I) <= ( FP16AddDenorm(RealPart(A), ImagPart(B), IntPrec_C),
                                        FP16SubtractDenorm(ImagPart(A), RealPart(B), IntPrec_C) );
              
              when others =>
                -- Invalid operation
                null;
            end case;
          end loop;
          
          DenormValid <= '1';
          DenormTag <= AVU_C_Tag;
          DenormRespond <= AVU_C_Respond;
        else
          -- Not doing anything
        
          DenormValid <= '0';
        end if;
      end if;
    end if;
  end process;
  
  --
  -- Normalize, result output
  --
  
  Normalizer_P : process(Clk)
    -- variable O : line;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        AVU_R_Present <= '0';

      elsif DenormValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C) <=
            Complex(NormalizeFP16(DenormResult(I).Real, IntPrec_C),
                       NormalizeFP16(DenormResult(I).Imag, IntPrec_C));

          -- if I = 0 then
          --   R0 := R;
          -- end if;
        end loop;

        AVU_R_Tag <= DenormTag;
        AVU_R_Present <= DenormRespond;

        -- Append(O, "Result ");
        -- write(O, to_integer(unsigned(DenormTag)));
        -- AppendCFP16(O, " = ", R0);
        
        -- writeline(output, O);
      else
        AVU_R_Present <= '0';
      end if;
    end if;
  end process;

  -- Report_P : process(Clk)
  --   variable O : line;
  -- begin
  --   if rising_edge(Clk) and Reset = '0' then
  --     if AVU_C_Present = '1' then
  --       case to_integer(unsigned(AVU_C_Operation)) is
  --         when 0 =>
  --           Append(O, "Multiply   ");
  --         when 1 =>
  --           Append(O, "Add        ");
  --         when 2 =>
  --           Append(O, "Subtract   ");
  --         when 3 =>
  --           Append(O, "Add rot i  ");
  --         when 4 =>
  --           Append(O, "Add rot -i ");
  --         when others =>
  --           Append(O, "Weird");
  --       end case;

  --       write(O, to_integer(unsigned(AVU_C_Tag)));
  --       AppendCFP16(O, " A = ", AVU_C_OperandA(WordSize_C-1 downto 0));
  --       AppendCFP16(O, " B = ", AVU_C_OperandB(WordSize_C-1 downto 0));
        
  --       writeline(output, O);
  --     end if;
  --   end if;
  -- end process;
end RTL;
