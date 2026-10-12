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

  function Complex(RealPart : Scalar_T; ImagPart : Scalar_T) return Word_T is
  begin
    return RealPart & ImagPart;
  end function;

  -- Non-normalized result of multiplication or addition
  
  subtype MultiplyResult_T is GenericFP_T(Mantissa(2*Precision_C-1 downto 0));
  
  subtype AddResult_T is GenericFP_T(Mantissa(1+Precision_C-1 downto 0));
  
  type PartialComplexMultiplyResult_T is record
    RealARealB : MultiplyResult_T;
    ImagAImagB : MultiplyResult_T;
    RealAImagB : MultiplyResult_T;
    ImagARealB : MultiplyResult_T;
  end record;

  subtype DenormMultiplyResult_T is GenericFP_T(Mantissa(1+2*Precision_C-1 downto 0));
  
  type DenormComplexMultiplyResult_T is record
    Real : DenormMultiplyResult_T;
    Imag : DenormMultiplyResult_T;
  end record;

  -- Non-normalized result of addition
  
  type DenormAddResult_T is record
    Real : AddResult_T;
    Imag : AddResult_T;
  end record;

  type PartialMultiplyResultArray_T is array (natural range <>) of PartialComplexMultiplyResult_T;

  type DenormMultiplyResultArray_T is array (natural range <>) of DenormComplexMultiplyResult_T;
  
  type DenormAddResultArray_T is array (natural range <>) of DenormAddResult_T;
  
  signal PartialMultiplyResult : PartialMultiplyResultArray_T(0 to 2**Log2VecSize_C-1);
  signal DenormMultiplyResult : DenormMultiplyResultArray_T(0 to 2**Log2VecSize_C-1);
  signal DenormAddResult : DenormAddResultArray_T(0 to 2**Log2VecSize_C-1);
  signal AddResult : WordArray_T(0 to 2**Log2VecSize_C-1);
  signal PartialValid, DenormValid : std_logic;
  signal PartialTag, DenormTag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal PartialOperation, DenormOperation : std_logic_vector(ExtOpSize_C-1 downto 0);
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
        PartialOperation <= (others => '0');

      elsif AVU_C_Present = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          A := AVU_C_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C);
          B := AVU_C_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C);

          case to_integer(unsigned(AVU_C_Operation(2 downto 0))) is
            when 0 =>
              -- A * B
            
              PartialMultiplyResult(I) <= ( FP16MultiplyDenorm(RealPart(A), RealPart(B)),
                                            FP16MultiplyDenorm(ImagPart(A), ImagPart(B)),
                                            FP16MultiplyDenorm(RealPart(A), ImagPart(B)),
                                            FP16MultiplyDenorm(ImagPart(A), RealPart(B)) );

            when 1 =>      
              -- A + B
            
              DenormAddResult(I) <= ( FP16AddDenorm(RealPart(A), RealPart(B)),
                                       FP16AddDenorm(ImagPart(A), ImagPart(B)) );
              
            when 2 =>      
              -- A - B
            
              DenormAddResult(I) <= ( FP16SubtractDenorm(RealPart(A), RealPart(B)),
                                       FP16SubtractDenorm(ImagPart(A), ImagPart(B)) );
              
            when 3 =>      
              -- A + iB
            
              DenormAddResult(I) <= ( FP16SubtractDenorm(RealPart(A), ImagPart(B)),
                                       FP16AddDenorm(ImagPart(A), RealPart(B)) );
              
            when 4 =>      
              -- A - iB
            
              DenormAddResult(I) <= ( FP16AddDenorm(RealPart(A), ImagPart(B)),
                                       FP16SubtractDenorm(ImagPart(A), RealPart(B)) );
              
            when others =>
              -- Invalid operation
              null;
          end case;
        end loop;

        PartialValid <= '1';
        PartialOperation <= AVU_C_Operation;
        PartialRespond <= AVU_C_Respond;
        PartialTag <= AVU_C_Tag;
      else
        PartialValid <= '0';
        PartialOperation <= (others => '0');
      end if;
    end if;
  end process;
  
  AVU_C_Accept <= '1';
  
  --
  -- Partial result adder
  --
  
  PartialAdder_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        DenormValid <= '0';

      elsif PartialValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          if to_integer(unsigned(PartialOperation(2 downto 0))) = 0 then
            -- Complex multiply, add partial terms with full precision
            
            DenormMultiplyResult(I).Real <= AddGenericFP(PartialMultiplyResult(I).RealARealB,
                                                     NegateGenericFP(PartialMultiplyResult(I).ImagAImagB));

            DenormMultiplyResult(I).Imag <= AddGenericFP(PartialMultiplyResult(I).RealAImagB,
                                                      PartialMultiplyResult(I).ImagARealB);
          else
            -- Complex add/sub/etc, normalize already
            
            AddResult(I)
              <= Complex(NormalizeFP16(DenormAddResult(I).Real, 0),
                         NormalizeFP16(DenormAddResult(I).Imag, 0));
          end if;
        end loop;

        DenormValid <= '1';
        DenormOperation <= PartialOperation;
        DenormTag <= PartialTag;
        DenormRespond <= PartialRespond;
      else
        DenormValid <= '0';
      end if;
    end if;
  end process;
  
  --
  -- Normalize, result output
  --
  
  Normalizer_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        AVU_R_Present <= '0';

      elsif DenormValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          if to_integer(unsigned(PartialOperation(2 downto 0))) = 0 then
            -- Complex multiply, normalize now
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C)
              <= Complex(NormalizeFP16(DenormMultiplyResult(I).Real, Precision_C),
                         NormalizeFP16(DenormMultiplyResult(I).Imag, Precision_C));
          else
            -- Complex add/sub/etc, was normalized during the previous stage
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C) <= AddResult(I);
          end if;
        end loop;

        AVU_R_Tag <= DenormTag;
        AVU_R_Present <= DenormRespond;
      else
        AVU_R_Present <= '0';
      end if;
    end if;
  end process;
end RTL;
