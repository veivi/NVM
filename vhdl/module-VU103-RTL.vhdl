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
  
  constant MantSize_C : integer := Precision_C - 1;  -- Implicit '1' not counted
  
  constant ExpSize_C : integer := ScalarSize_C - 1 - MantSize_C; -- -1 is for sign

  constant ExpBias_C : integer := 2**ExpSize_C/2 + 1;
  
  subtype Scalar_T is std_logic_vector(ScalarSize_C-1 downto 0);

  subtype Mantissa_T is std_logic_vector(Precision_C-1 downto 0);  -- With implicit
                                                                   -- '1'

  constant ExtMantSize_C : integer := Precision_C + 2;
  
  subtype ExtMantissa_T is signed(ExtMantSize_C-1 downto 0); 

  subtype DoubleMantissa_T is unsigned(2*Precision_C-1 downto 0); 

  subtype Exp_T is integer range 0 to 2**ExpSize_C-1;

  subtype ExtExp_T is integer range -2*2**ExpSize_C to 2*2**ExpSize_C-1;  -- Extended
  
  function ScalarSign(A : Scalar_T) return std_logic is
  begin
    return A(ScalarSize_C-1);
  end function;

  function ScalarExp(A : Scalar_T) return Exp_T is
  begin
    return to_integer(unsigned(A(ScalarSize_C-2 downto MantSize_C)));
  end function;
  
  function ScalarMant(A : Scalar_T) return Mantissa_T is
  begin
    if ScalarExp(A) = 0 then
      -- It's a +/- zero
      return (others => '0');
    else
      -- Not zero, add the implied leading '1'
      return '1' & A(MantSize_C-1 downto 0);
    end if;
  end function;

  function ScalarMake(Sign : std_logic; E : Exp_T; M : Mantissa_T) return Scalar_T is
    variable T : std_logic_vector(ScalarSize_C-1 downto 0);
  begin
    return Sign & std_logic_vector(to_unsigned(E, ExpSize_C)) & M(MantSize_C-1 downto 0);
  end function;
  
  function ExtendMant(A : Mantissa_T) return ExtMantissa_T is
    variable T : ExtMantissa_T;
  begin
    T := (others => '0');
    T(Precision_C-1 downto 0) := signed(A);
    return T;
  end function;
  
  -- Non-normalized result of addition
  
  type AddResult_T is record
    Sign : std_logic;
    Exp : Exp_T;
    Mantissa : ExtMantissa_T;
  end record;

  -- Non-normalized result of multiplication
  
  type MultiplyResult_T is record
    Sign : std_logic;
    Exp : ExtExp_T;
    Mantissa : DoubleMantissa_T;
  end record;

  function NegateFP16(A : Scalar_T) return Scalar_T is
  begin
    return ScalarMake(not ScalarSign(A), ScalarExp(A), ScalarMant(A));
  end function;
  
  function AddFP16(A : Scalar_T; B : Scalar_T) return AddResult_T is
    variable Bigger, Smaller : Scalar_T;
    variable ExpBig, ExpSmall : Exp_T;
    variable MantBig, MantSmall : ExtMantissa_T;
    variable Sign : std_logic;
  begin
    if ScalarExp(A) >= ScalarExp(B) then
      Bigger := A;
      Smaller := B;
    else
      Bigger := B;
      Smaller := A;
    end if;

    ExpBig := ScalarExp(Bigger);
    MantBig := ExtendMant(ScalarMant(Bigger));
    ExpSmall := ScalarExp(Smaller);
    MantSmall := shift_right(ExtendMant(ScalarMant(Smaller)), ExpBig - ExpSmall);

    if ScalarSign(Bigger) = '1' then
      MantBig := -MantBig;
    end if;

    if ScalarSign(Smaller) = '1' then
      MantSmall := -MantSmall;
    end if;

    MantBig := MantBig + MantSmall;

    Sign := MantBig(Precision_C);

    if Sign = '1' then
      MantBig := -MantBig;
    end if;

    return ( Sign => Sign, Exp => ExpBig, Mantissa => MantBig );
  end function;

  function Normalize(A : AddResult_T) return Scalar_T is
    variable Exp : ExtExp_T;
    variable Mant : ExtMantissa_T;
  begin
    Exp := A.Exp;
    Mant := A.Mantissa;

    if Mant > to_signed(2**Precision_C, ExtMantSize_C) then
      -- TOo big, shift one right and increment exponent
      if Exp < 2**ExpSize_C-1 then
        -- We have room in the exponent
        Exp := Exp + 1;
        Mant := shift_right(Mant, 1);
      else
        -- Overflow to max
        Mant := (others => '1');
      end if;
      
    elsif Mant /= to_signed(0, ExtMantSize_C) then
      -- Not zero, normalize if needed by shifting left

      while Mant(Precision_C) = '0' and Exp > 0 loop
        Exp := Exp - 1;
        Mant := shift_left(Mant, 1);
      end loop;
    end if;

    if Exp < 1 then
      -- Underflow to zero
      Mant := (others => '0');
    end if;
    
    return ScalarMake(A.Sign, Exp, std_logic_vector(Mant(MantSize_C-1 downto 0)));
  end function;

  function MultiplyFP16(A : Scalar_T; B : Scalar_T) return MultiplyResult_T is
    variable Sign : std_logic;
    variable Exp : ExtExp_T;
    variable Mant : DoubleMantissa_T;
  begin
    Sign := ScalarSign(A) xor ScalarSign(B);
    Exp := ScalarExp(A) + ScalarExp(B) - ExpBias_C;
    Mant := unsigned(ScalarMant(A)) * unsigned(ScalarMant(B));

    return ( Sign => Sign, Exp => Exp, Mantissa => Mant);
  end function;

  function Negate(A : MultiplyResult_T) return MultiplyResult_T is
  begin
    return ( Sign => not A.Sign, Exp => A.Exp, Mantissa => A.Mantissa );
  end function;
  
  function Add(A : MultiplyResult_T; B : MultiplyResult_T) return MultiplyResult_T is
  begin
    -- FIXME: Implement!
  end function;
    
  function Normalize(A : MultiplyResult_T) return Scalar_T is
    variable Exp : ExtExp_T;
    variable Mant : DoubleMantissa_T;
  begin
    Exp := A.Exp;
    Mant := A.Mantissa;
    
    if Mant > to_unsigned(2*2**Precision_C, 2*MantSize_C) then
      -- Adjust exponent
      Exp := Exp - 1;
      Mant := shift_right(Mant, 1);
    end if;

    if Exp > 2**ExpSize_C-1 then
      -- Overflow to max
      Exp := 2**ExpSize_C-1;
      Mant := (others => '1');
    elsif Exp = 0 or Mant = to_unsigned(0, 2*MantSize_C) then
      -- The result is zero
      Exp := 0;
      Mant := (others => '0');
    end if;

    return ScalarMake(A.Sign, Exp,
                      std_logic_vector(Mant(Precision_C+MantSize_C-1 downto Precision_C)));
  end function;

  type PartialMultiplyResult_T is record
    RealARealB : MultiplyResult_T;
    ImagAImagB : MultiplyResult_T;
    RealAImagB : MultiplyResult_T;
    ImagARealB : MultiplyResult_T;
  end record;

  type PartialAddResult_T is record
    Real : AddResult_T;
    Imag : AddResult_T;
  end record;

  type PartialMultiplyResultArray_T is array (natural range <>) of PartialMultiplyResult_T;
  
  type PartialAddResultArray_T is array (natural range <>) of PartialAddResult_T;
  
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

  signal PartialMultiplyResult : PartialMultiplyResultArray_T(0 to 2**Log2VecSize_C-1);
  signal PartialAddResult : PartialAddResultArray_T(0 to 2**Log2VecSize_C-1);
  signal MultiplyResult : WordArray_T(0 to 2**Log2VecSize_C-1);
  signal PartialValid, MultiplyValid : std_logic;
  signal PartialTag, MultiplyTag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal PartialOperation, MultiplyOperation : std_logic_vector(ExtOpSize_C-1 downto 0);
  signal PartialRespond, MultiplyRespond : std_logic;
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
            
              PartialMultiplyResult(I) <= ( MultiplyFP16(RealPart(A), RealPart(B)),
                                            MultiplyFP16(ImagPart(A), ImagPart(B)),
                                            MultiplyFP16(RealPart(A), ImagPart(B)),
                                            MultiplyFP16(ImagPart(A), RealPart(B)) );

            when 1 =>      
              -- A + B
            
              PartialAddResult(I) <= ( AddFP16(RealPart(A), RealPart(B)),
                                       AddFP16(ImagPart(A), ImagPart(B)) );
              
            when 2 =>      
              -- A - B
            
              PartialAddResult(I) <= ( AddFP16(RealPart(A), NegateFP16(RealPart(B))),
                                       AddFP16(ImagPart(A), NegateFP16(ImagPart(B))) );
              
            when 3 =>      
              -- A + iB
            
              PartialAddResult(I) <= ( AddFP16(RealPart(A), NegateFP16(ImagPart(B))),
                                       AddFP16(ImagPart(A), RealPart(B)) );
              
            when 4 =>      
              -- A - iB
            
              PartialAddResult(I) <= ( AddFP16(RealPart(A), ImagPart(B)),
                                       AddFP16(ImagPart(A), NegateFP16(RealPart(B))) );
              
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

  --
  -- Partial result adder, result output
  --
  
  PartialAdder_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        AVU_R_Present <= '0';

      elsif PartialValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          if to_integer(unsigned(PartialOperation(2 downto 0))) = 0 then
            -- Complex multiply
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C)
              <= Complex(Normalize(Add(PartialMultiplyResult(I).RealARealB,
                                       Negate(PartialMultiplyResult(I).ImagAImagB))),
                         Normalize(Add(PartialMultiplyResult(I).RealAImagB,
                                       PartialMultiplyResult(I).ImagARealB)));
          else
            -- Complex add/sub/etc
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C)
              <= Complex(Normalize(PartialAddResult(I).Real),
                         Normalize(PartialAddResult(I).Imag));
          end if;
        end loop;

        AVU_R_Tag <= PartialTag;
        AVU_R_Present <= PartialRespond;
      else
        AVU_R_Present <= '0';
      end if;
    end if;
  end process;
  
  AVU_C_Accept <= '1';
end RTL;
