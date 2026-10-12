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
use WORK.SignalMath.all;
use std.textio.all;

entity FP16Testbench is
end entity;

architecture Bhv of FP16Testbench is
  procedure PrintFP16(T : in string; A : in FP16_T) is
    variable L : line;
  begin
    write(L, T);
    write(L, string'(" Sign="));
    write(L, FP16Sign(A));
    write(L, string'(" Exp="));
    write(L, FP16Exp(A));
    write(L, string'(" Mant="));
    write(L, FP16Mant(A));
    writeline(output, L);
  end procedure;
  
begin
  process
    variable OutLine : line;
    variable A, B, T : FP16_T;
  begin
    A := "0100000100110000";
    B := "0011100100110000";
    T := (others => '0');

    PrintFP16("A", A);
    
    T := FP16Add(T, A);
    PrintFP16("T=T+A", T);
    
    T := FP16Add(T, A);
    PrintFP16("T=T+A", T);

    T := FP16Add(T, A);
    PrintFP16("T=T+A", T);

    T := FP16Add(T, A);
    PrintFP16("T=T+A", T);

    T := FP16Subtract(T, T);
    PrintFP16("T=T-T", T);
    
    T := FP16Subtract(T, A);
    PrintFP16("T=T-A", T);

    T := FP16Subtract(T, A);
    PrintFP16("T=T-A", T);

    T := FP16Subtract(T, A);
    PrintFP16("T=T-A", T);

    PrintFP16("B=", B);

    T := FP16Multiply(A, B);
    PrintFP16("T=A*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);

     T := FP16Multiply(T, B);
    PrintFP16("T=T*B", T);
    wait;
  end process;
end Bhv;
