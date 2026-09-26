library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Types.all;
use WORK.NVM101Interface.all;

entity VRFU is
  generic(Log2BPW_C : integer;
          Log2NumOfRegs_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       --
       -- Scoreboard control
       --

       SB_Set : in std_logic;
       SB_Index : in RegIndex_T;
       SB_Span : in RegSpan_T;

       --
       -- Interlock interface
       --
       
       DecodeStall : in std_logic;
       ExecuteStall : in std_logic;
       RF_ReadValid : out std_logic;
       
       --
       -- Scoreboard output
       --

       Scoreboard : out std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
       
       --
       -- Read ports A, B, C
       --

       RA_Active : in std_logic;
       RA_Index : in RegIndex_T;
       RA_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       RB_Active : in std_logic;
       RB_Index : in RegIndex_T;
       RB_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       RC_Active : in std_logic;
       RC_Index : in RegIndex_T;
       RC_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       --
       -- Write ports A, B
       --

       WA_Active : in std_logic;
       WA_Async : in std_logic;
       WA_Valid : in std_logic;
       WA_Index : in RegIndex_T;
       WA_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       WB_Active : in std_logic;
       WB_Index : in RegIndex_T;
       WB_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));      
end VRFU;

architecture RTL of VRFU is
  constant WordSize_C : integer := ByteSize_C * 2**Log2BPW_C;
  
  subtype Word_T is std_logic_vector(WordSize_C-1 downto 0);
  type WordArray_T is array(natural range <>) of Word_T;

  signal Storage : WordArray_T(0 to 2**Log2NumOfRegs_C);
  signal Set, Clear, State : std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
  
begin
  --
  -- Scoreboard storage
  --

  Scoreboard_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        State <= (others => '0');
      else
        State <= (State and not Clear) or Set;        
      end if;  
    end if;
  end process;

  Scoreboard <= State;
  
  Clear_P : process(ExecuteStall, WA_Active, WA_Index, WB_Active, WB_Index)
  begin
    Clear <= (others => '0');
    Clear(WA_Index) <= WA_Active and (WA_Async or not ExecuteStall);
    Clear(WB_Index) <= WB_Active;
  end process;

  Set_P : process(DecodeStall, ExecuteStall, SB_Set, SB_Index, SB_Span)
    variable Last : std_logic_vector(Log2NumOfRegs_C-1 downto 0);
  begin
    Set <= (others => '0');
    Last := std_logic_vector(to_unsigned(SB_Index, Log2NumOfRegs_C))
          or std_logic_vector(to_unsigned(SB_Span, Log2NumOfRegs_C));
    for I in SB_Index to to_integer(unsigned(Last)) loop
      Set(I) <= SB_Set and not DecodeStall and not ExecuteStall;
    end loop; 
  end process;

  --
  -- Register storage
  --

  Storage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if WA_Active = '1' and WA_Valid = '1' then
        Storage(WA_Index) <= WA_Data;
      end if;
      
      if WB_Active = '1' then
        Storage(WB_Index) <= WB_Data;
      end if;
    end if;
  end process;

  --
  -- Register access including feed-forward
  --

  ReadPortA_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if ExecuteStall = '0' then
        if RA_Active = '1' then
          if WA_Active = '1' and WA_Index = RA_Index then
            -- Feed-forward from port A
            RA_Data <= WA_Data;
          else
            RA_Data <= Storage(RA_Index);
          end if;
        end if;
      end if;
    end if;
  end process;

  ReadPortB_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if ExecuteStall = '0' then
        if RB_Active = '1' then
          if WA_Active = '1' and WA_Index = RB_Index then
            -- Feed-forward from port A
            RB_Data <= WA_Data;
          else
            RB_Data <= Storage(RB_Index);
          end if;
        end if;
      end if;
    end if;
  end process;

  ReadPortC_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if ExecuteStall = '0' then
        if RC_Active = '1' then
          if WA_Active = '1' and WA_Index = RC_Index then
            -- Feed-forward from port A
            RC_Data <= WA_Data;
          else
            RC_Data <= Storage(RC_Index);
          end if;
        end if;
      end if;
    end if;
  end process;
  
  Status_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if ExecuteStall = '0' then
        RF_ReadValid <= not DecodeStall;
      end if;
    end if;
  end process;  
end RTL;

