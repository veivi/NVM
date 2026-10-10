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
end package;
