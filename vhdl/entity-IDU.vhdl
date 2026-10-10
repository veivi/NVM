-------------------------------------------------------------------------------
-- Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
-- 
-- PROPRIETARY AND CONFIDENTIAL.
-- Unauthorized copying, modification, or distribution of this file, 
-- via any medium, is strictly prohibited.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity IDU is
  generic(Log2BPW_C : integer;
          Log2NumOfRegs_C : integer);
          
  port(I_Code : in std_logic_vector(InstrSize_C-1 downto 0);
       ControlWord : out ControlWord_T;
       Imm_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end IDU;
