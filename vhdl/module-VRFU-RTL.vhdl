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
       -- ALU Read ports A, B, C
       --

       RA_Active : in std_logic;
       RA_Index : in RegIndex_T;
       RA_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       RB_Active : in std_logic;
       RB_Index : in RegIndex_T;
       RB_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       --
       -- ALU Write port A, B
       --

       WA_Active : in std_logic;
       WA_Async : in std_logic;  -- Tells if this write is coming from an AVU
       WA_Valid : in std_logic;
       WA_Index : in RegIndex_T;
       WA_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       --
       -- LSU read port
       --

       LS_ReadActive : in std_logic;
       LS_ReadIndex : in RegIndex_T;
       LS_ReadData : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       --
       -- LSU write port
       --
       
       LS_WriteActive : in std_logic;
       LS_WriteIndex : in RegIndex_T;
       LS_WriteData : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));      
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
  
  Clear_P : process(ExecuteStall, WA_Index, WA_Active, WA_Async,
                    LS_ReadActive, LS_ReadIndex, LS_WriteActive, LS_WriteIndex)
  begin
    Clear <= (others => '0');
    if WA_Active = '1' and (WA_Async or not ExecuteStall) = '1' then
      Clear(WA_Index) <= '1';
    end if;

    if LS_WriteActive = '1' then
      Clear(LS_WriteIndex) <= '1';
    end if;

    if LS_ReadActive = '1' then
      Clear(LS_ReadIndex) <= '1';
    end if;
  end process;

  Set_P : process(DecodeStall, ExecuteStall, SB_Set, SB_Index, SB_Span)
    variable Last : std_logic_vector(Log2NumOfRegs_C-1 downto 0);
  begin
    Set <= (others => '0');

    Last := std_logic_vector(to_unsigned(SB_Index, Log2NumOfRegs_C))
          or std_logic_vector(to_unsigned(2**SB_Span-1, Log2NumOfRegs_C));

    for I in 0 to 2**Log2NumOfRegs_C-1 loop
      if I >= SB_Index and I <= to_integer(unsigned(Last)) then
        Set(I) <= SB_Set and not DecodeStall and not ExecuteStall;
      end if;
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
      
      if LS_WriteActive = '1' then
        Storage(LS_WriteIndex) <= LS_WriteData;
      end if;
    end if;
  end process;

  --
  -- Register access including feed-forward
  --

  ReadPortA_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        RA_Data <= (others => '0');

      elsif ExecuteStall = '0' then
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
      if Reset = '1' then
        RB_Data <= (others => '0');
        
      elsif ExecuteStall = '0' then
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

 ReadPortLS_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        LS_ReadData <= (others => '0');

      elsif LS_ReadActive = '1' then
        if ExecuteStall = '0' and WA_Active = '1' and WA_Index = LS_ReadIndex then
          -- Feed-forward from port A
          LS_ReadData <= WA_Data;
        else
          LS_ReadData <= Storage(LS_ReadIndex);
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

