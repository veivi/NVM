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

package body SignalMath is
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
    if A(A'range'high) = '1' then
      return Negate(A);
    else
      return A;
    end if;
  end function;

  --
  -- FP16
  --

  function FP16Sign(A : FP16_T) return std_logic is
  begin
    return A(FP16Size_C-1);
  end function;

  function FP16Exp(A : FP16_T) return FP16Exp_T is
  begin
    return to_integer(unsigned(A(FP16Size_C-2 downto FP16MantSize_C)));
  end function;
  
  function FP16Mant(A : FP16_T) return FP16Mantissa_T is
  begin
    if FP16Exp(A) = 0 then
      -- It's a +/- zero
      return (others => '0');
    else
      -- Not zero, add the implied leading '1'
      return unsigned('1' & A(FP16MantSize_C-1 downto 0));
    end if;
  end function;

  function FP16Make(Sign : std_logic; E : FP16Exp_T; M : FP16Mantissa_T) return FP16_T is
  begin
    return Sign & std_logic_vector(to_unsigned(E, FP16ExpSize_C))
      & std_logic_vector(M(FP16MantSize_C-1 downto 0));
  end function;
  
  function GenericFPFromFP16(A : FP16_t) return GenericFP_T is
  begin
    return ( Sign => FP16Sign(A), Exp => FP16Exp(A), Mantissa => FP16Mant(A) );
  end function;
  
  function FP16Neg(A : FP16_T) return FP16_T is
  begin
    return FP16Make(not FP16Sign(A), FP16Exp(A), FP16Mant(A));
  end function;
  
  function FP16Add(A : FP16_T; B : FP16_T) return FP16_T is
  begin
    return NormalizeFP16(AddGenericFP(GenericFPFromFP16(A), GenericFPFromFP16(B)), 0);
  end function;
  
  function FP16Subtract(A : FP16_T; B : FP16_T) return FP16_T is
  begin
    return FP16Add(A, FP16Neg(B));
  end function;
  
  function FP16Multiply(A : FP16_T; B : FP16_T) return FP16_T is
  begin
    return NormalizeFP16(MultiplyGenericFP(GenericFPFromFP16(A), GenericFPFromFP16(B)), FP16Prec_C);
  end function;
  
  function FP16AddDenorm(A : FP16_T; B : FP16_T) return GenericFP_T is
  begin
    return AddGenericFP(GenericFPFromFP16(A), GenericFPFromFP16(B));
  end function;
  
  function FP16SubtractDenorm(A : FP16_T; B : FP16_T) return GenericFP_T is
  begin
    return FP16AddDenorm(A, FP16Neg(B));
  end function;
  
  function FP16MultiplyDenorm(A : FP16_T; B : FP16_T) return GenericFP_T is
  begin
    return MultiplyGenericFP(GenericFPFromFP16(A), GenericFPFromFP16(B));
  end function;
  
  --
  -- Generic FP addition, result is not normalized
  --
    
  function AddGenericFP(A : GenericFP_T; B : GenericFP_T) return GenericFP_T is
    -- Extended mantissa must hold negative values and the result of addition,
    -- so two extra bits needed
    variable ExtMantSize_C : integer := A.Mantissa'range'high - A.Mantissa'range'low + 3;
    variable Bigger, Smaller : GenericFP_T(Mantissa(A.Mantissa'range));
    variable Exp, ExpSmall : FP16ExtExp_T;
    variable Mant, MantSmall : unsigned(ExtMantSize_C-1 downto 0);
    variable Sign : std_logic;
  begin
    if A.Exp >= B.Exp then
      Bigger := A;
      Smaller := B;
    else
      Bigger := B;
      Smaller := A;
    end if;

    Exp := Bigger.Exp;
    Mant := resize(Bigger.Mantissa, ExtMantSize_C);
    
    ExpSmall := Smaller.Exp;
    MantSmall := shift_right(resize(Smaller.Mantissa, ExtMantSize_C), Exp - ExpSmall);

    if Bigger.Sign = '1' then
      Mant := unsigned(-signed(Mant));
    end if;

    if Smaller.Sign = '1' then
      MantSmall := unsigned(-signed(MantSmall));
    end if;

    Mant := Mant + MantSmall;

    Sign := Mant(ExtMantSize_C-1);

    if Sign = '1' then
      Mant := unsigned(-signed(Mant));
    end if;
    
    return ( Sign => Sign, Exp => Exp, Mantissa => Mant(ExtMantSize_C-2 downto 0) );
  End;

  function MultiplyGenericFP(A : GenericFP_T; B : GenericFP_T) return GenericFP_T is
    constant ExtMantSize_C : integer := A.Mantissa'range'high - A.Mantissa'range'low + 1
                                        + B.Mantissa'range'high - B.Mantissa'range'low + 1;
    variable Exp : FP16ExtExp_T;
    variable Mant : unsigned(ExtMantSize_C-1 downto 0);
  begin
    Exp := A.Exp + B.Exp - FP16ExpBias_C;
    Mant := unsigned(A.Mantissa) * unsigned(B.Mantissa);

    if Exp < 1 or Mant = to_unsigned(0, ExtMantSize_C) then
      -- Underflow
      Exp := 0;
      Mant := (others => '0');
    end if;
    
    return ( Sign => A.Sign xor B.Sign, Exp => Exp, Mantissa => Mant);
  end function;
  
  function NegateGenericFP(A : GenericFP_T) return GenericFP_T is
  begin
    return ( Sign => not A.Sign, Exp => A.Exp, Mantissa => A.Mantissa );
  end function;

  function NormalizeFP16(A : GenericFP_T; PrecDelta : integer) return FP16_T is
    constant ExtMantSize_C : integer := A.Mantissa'range'high - A.Mantissa'range'low + 2;
    variable Exp : FP16ExtExp_T;
    variable Mant : unsigned(ExtMantSize_C-1 downto 0);
  begin
    Exp := A.Exp;
    Mant := resize(A.Mantissa, ExtMantSize_C);

    if Exp > 2**FP16ExpSize_C-1 then
      -- Overflow
      Exp := 2**FP16ExpSize_C-1;
      Mant := (others => '1');
      
    elsif unsigned(Mant(ExtMantSize_C-1 downto FP16Prec_C+PrecDelta)) > 0 then
      -- Bigger than one, shift one right and increment exponent
      if Exp < 2**FP16ExpSize_C-1 then
        -- We have room in the exponent
        Exp := Exp + 1;
        Mant := shift_right(Mant, 1);
      else
        -- Overflow to max
        Exp := 2**FP16ExpSize_C-1;
        Mant := (others => '1');
      end if;
    
    elsif Mant /= to_unsigned(0, ExtMantSize_C) then
      -- Not zero, normalize if needed by shifting left until between 0.5 and 1

      while Mant(FP16Prec_C+PrecDelta-1) = '0' and Exp > 0 loop
        Exp := Exp - 1;
        Mant := shift_left(Mant, 1);
      end loop;
    else
      -- Result is zero
      Exp := 0;
    end if;

    if Exp < 1 then
      -- Underflow to zero
      Exp := 0;
      Mant := (others => '0');
    end if;
    
    return FP16Make(A.Sign, Exp, Mant(PrecDelta+FP16Prec_C-1 downto PrecDelta));
  end function;

end package body;
