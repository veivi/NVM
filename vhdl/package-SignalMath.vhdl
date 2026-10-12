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

package SignalMath is
  function Saturate(A : std_logic_vector; W : natural) return std_logic_vector;
  
  function Add(A : std_logic_vector; B : std_logic_vector) return std_logic_vector;

  function Negate(A : std_logic_vector) return std_logic_vector;

  function Absolute(A : std_logic_vector) return std_logic_vector;

  constant FP16Size_C : integer := 16;
  
  constant FP16Prec_C : integer := 12;

  subtype FP16_T is std_logic_vector(FP16Size_C-1 downto 0);

  constant FP16MantSize_C : integer := FP16Prec_C - 1;

  constant FP16ExpSize_C : integer := FP16Size_C - 1 - FP16MantSize_C;
  
  constant FP16ExpBias_C : integer := 2**FP16ExpSize_C/2 - 1;
  
  subtype FP16Exp_T is integer range 0 to 2**FP16ExpSize_C-1;

  subtype FP16ExtExp_T is integer range -2*2**FP16ExpSize_C to 2*2**FP16ExpSize_C-1;

  subtype FP16Mantissa_T is unsigned(FP16Prec_C-1 downto 0);
  
  type GenericFP_T is record
    Sign : std_logic;
    Exp : FP16ExtExp_T;
    Mantissa : unsigned;
  end record;

  function FP16Sign(A : FP16_T) return std_logic;
  function FP16Exp(A : FP16_T) return FP16Exp_T;
  function FP16Mant(A : FP16_T) return FP16Mantissa_T;
  function FP16Make(Sign : std_logic; E : FP16Exp_T; M : FP16Mantissa_T) return FP16_T;
  function FP16Neg(A : FP16_T) return FP16_T;
  function FP16Add(A : FP16_T; B : FP16_T) return FP16_T;
  function FP16Subtract(A : FP16_T; B : FP16_T) return FP16_T;
  function FP16Multiply(A : FP16_T; B : FP16_T) return FP16_T;
  function FP16AddDenorm(A : FP16_T; B : FP16_T) return GenericFP_T;
  function FP16SubtractDenorm(A : FP16_T; B : FP16_T) return GenericFP_T;
  function FP16MultiplyDenorm(A : FP16_T; B : FP16_T) return GenericFP_T;

  function GenericFPFromFP16(A : FP16_t) return GenericFP_T;
  function AddGenericFP(A : GenericFP_T; B : GenericFP_T) return GenericFP_T;
  function MultiplyGenericFP(A : GenericFP_T; B : GenericFP_T) return GenericFP_T;
  function NegateGenericFP(A : GenericFP_T) return GenericFP_T;
  function NormalizeFP16(A : GenericFP_T; PrecDelta : integer) return FP16_T;
end package;
