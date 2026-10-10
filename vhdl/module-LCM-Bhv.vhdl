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

entity LCM is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          TagSize_C : integer);
  
  port(Clk : in std_logic;
       Reset : in std_logic;
       
       LCI_Present : in std_logic;
       LCI_Accept : out std_logic;
       LCI_Write : in std_logic;
       LCI_Tag : in std_logic_vector(TagSize_C-1 downto 0);
       LCI_Addr : in std_logic_vector(AddrSize_C-1 downto 0);
       LCI_ByteSel : in std_logic_vector(2**Log2BPW_C-1 downto 0);
       LCI_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       LCR_Present : out std_logic;
       LCR_Tag : out std_logic_vector(TagSize_C-1 downto 0);
       LCR_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end LCM;

architecture Bhv of LCM is
  constant Log2MemSize_C : integer := 10;
  
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  
  subtype Word_T is std_logic_vector(WordSize_C-1 downto 0);

  type WordArray_T is array (natural range <>) of Word_T;

  signal Storage : WordArray_T(0 to 2**Log2MemSize_C-1);

  type State_T is ( Idle_C, Read_C, Write_C );

  signal State : State_T;
  signal Addr : integer range 0 to 2**Log2MemSize_C-1;
  signal ByteSel : std_logic_vector(2**Log2BPW_C-1 downto 0);
  signal Tag : std_logic_vector(TagSize_C-1 downto 0);
  signal WriteData : Word_T;
begin
  State_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if LCI_Present = '1' then
        if LCI_Write = '1' then
          State <= Write_C;
          WriteData <= LCI_Data;
        else
          State <= Read_C;
        end if;

        Tag <= LCI_Tag;
        Addr <= to_integer(unsigned(LCI_Addr(Log2MemSize_C-1 downto 0)));
        ByteSel <= LCI_ByteSel;
      else
        State <= Idle_C;
      end if;
    end if;
  end process;

  Storage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if State = Write_C then
        for I in 0 to 2**Log2BPW_C-1 loop
          if ByteSel(I) = '1' then
            Storage(Addr)((I+1)*ByteSize_C-1 downto I*ByteSize_C)
              <= WriteData((I+1)*ByteSize_C-1 downto I*ByteSize_C);
          end if;
        end loop;
      end if;
    end if;
  end process;
  
  Responder_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        LCR_Present <= '0';
        LCR_Tag <= (others => '0');
        LCR_Data <= (others => '0');
        
      elsif State = Read_C then
        LCR_Present <= '1';
        LCR_Tag <= Tag;
        LCR_Data <= (others => 'X');
        for I in 0 to 2**Log2BPW_C-1 loop
          if ByteSel(I) = '1' then
            LCR_Data((I+1)*ByteSize_C-1 downto I*ByteSize_C)
              <= Storage(Addr)((I+1)*ByteSize_C-1 downto I*ByteSize_C);
          end if;
        end loop;
      else
        LCR_Present <= '0';
        LCR_Tag <= (others => '0');
      end if;
    end if;
  end process;

  LCI_Accept <= '1'; -- TODO: Add variable blocking
end Bhv;

  
