library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity VLSU is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          TagSize_C : integer;
          Log2TableSize_C : integer;
          Log2NumOfRegs_C : integer);
          
  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Command interface

       C_Operation : in LoadStoreOp_T;
       C_Log2Size : in SizeSpec_T;
       C_Stall : in std_logic;
       C_Ready : out std_logic;
       C_Span : in RegSpan_T;
       C_Dest : in RegIndex_T;
       C_Addr : in std_logic_vector(AddrSize_C-1 downto 0);
       C_Stride : in std_logic_vector(AddrSize_C-1 downto 0);
       C_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       -- Result (load data) interface

       LS_WriteActive : out std_logic;
       LS_WriteIndex : out RegIndex_T;
       LS_WriteData : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       -- Store data read interface

       LS_ReadActive : out std_logic;
       LS_ReadIndex : out RegIndex_T;
       LS_ReadData : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       -- Status

       LoadsOutstanding : out std_logic;
       StoresOutstanding : out std_logic;
       
       -- LCM initiative

       LCI_Present : out std_logic;
       LCI_Accept : in std_logic;
       LCI_Write : out std_logic;
       LCI_Tag : out std_logic_vector(TagSize_C-1 downto 0);
       LCI_Addr : out std_logic_vector(AddrSize_C-Log2BPW_C-1 downto 0);
       LCI_ByteSel : out std_logic_vector(2**Log2BPW_C-1 downto 0);
       LCI_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);

       -- LCM response

       LCR_Present : in std_logic;
       LCR_Tag : in std_logic_vector(TagSize_C-1 downto 0);
       LCR_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end VLSU;   

architecture RTL of VLSU is
  constant Log2BufferDepth_C : integer := 2;

  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  
  subtype Lifetime_T is integer range 0 to 2**4-1;

  type BufferEntry_T is record
    State : LoadStoreOp_T;
    Addr : std_logic_vector(AddrSize_C-1 downto 0);
    Log2Size : integer range 0 to 2*Log2BPW_C-1;
    Stride : std_logic_vector(AddrSize_C-1 downto 0);
    Count : integer range 0 to 2**Log2MaxSpan_C-1;
    Dest : RegIndex_T;
  end record;

  constant IdleBufferEntry_C : BufferEntry_T :=
    ( LSOp_None_C, (others => '0'), 0, (others => '0'), 0, 0);

  type BufferArray_T is array(natural range <>) of BufferEntry_T;

  type WorkEntry_T is record
    State : LoadStoreOp_T;
    Addr : integer range 0 to 2**Log2BPW_C-1;
    Log2Size : integer range 0 to 2*Log2BPW_C-1;
    Lifetime : Lifetime_T;
    Dest : RegIndex_T;
  end record;

  constant EmptyWorkEntry_C : WorkEntry_T := ( LSOp_None_C, 0, 0, 0, 0 );
  
  type WorkArray_T is array(natural range <>) of WorkEntry_T;

  signal BufferStore : BufferArray_T(0 to 2**Log2BufferDepth_C-1);

  signal IndexIn, IndexOut : integer range 0 to 2**Log2BufferDepth_C-1;
  signal BufferFull, BufferEmpty : boolean;
  
  signal WorkTable : WorkArray_T(0 to 2**Log2TableSize_C-1);

  signal FreeIndex, ResponseIndex : integer range 0 to 2**Log2TableSize_C-1;
  
  signal SeeingValidResponse, WorkTableFull, ReadsOutstanding, WritesOutstanding,
    ReadsPending, WritesPending : boolean;
begin
  --
  -- Transaction buffer storage
  --

  BufferStore_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        -- Reset
        
        for I in 0 to 2**Log2BufferDepth_C-1 loop
          BufferStore(I) <= IdleBufferEntry_C;
        end loop;
        
      else
        if C_Operation /= LSOp_None_C and C_Stall = '0' and not BufferFull then
          --
          --  We're seeing a command and can buffer it
          --

          BufferStore(IndexIn).State <= C_Operation;
          BufferStore(IndexIn).Log2Size <= C_Log2Size;
          BufferStore(IndexIn).Addr <= C_Addr;
          BufferStore(IndexIn).Stride <= C_Stride;
          BufferStore(IndexIn).Dest <= C_Dest;
          BufferStore(IndexIn).Count <= 2**C_Span - 1;
        end if;

        if not BufferEmpty and not WorkTableFull and LCI_Accept = '1' then
          -- We can proceed
          
          if BufferStore(IndexOut).Count > 0 then
            -- Update outgoing address and count
          
            BufferStore(IndexOut).Addr <=
              std_logic_vector(unsigned(BufferStore(IndexOut).Addr) + unsigned(BufferStore(IndexOut).Stride));
            BufferStore(IndexOut).Count <= BufferStore(IndexOut).Count - 1;
            BufferStore(IndexOut).Dest <= ( BufferStore(IndexOut).Dest + 1 ) mod 2**Log2NumOfRegs_C;
          else
            -- Retire the entry
            
            BufferStore(IndexOut) <= IdleBufferEntry_C;
          end if;
        end if;
      end if;
    end if;
  end process;

  --
  -- Transaction buffer index storage
  --

  BufferIndexIn_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        IndexIn <= 0;
      elsif C_Operation /= LSOp_None_C and C_Stall = '0' and not BufferFull then
        IndexIn <= ( IndexIn + 1 ) mod 2**Log2BufferDepth_C;
      end if;
    end if;
  end process;
  
  BufferIndexOut_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        IndexOut <= 0;
      elsif not BufferEmpty and BufferStore(IndexOut).Count = 0 and not WorkTableFull and LCI_Accept = '1' then
        IndexOut <= ( IndexOut + 1 ) mod 2**Log2BufferDepth_C;
      end if;
    end if;
  end process;

  --
  -- Buffer state decode
  --

  BufferFull <= ( IndexIn + 1 ) mod 2**Log2BufferDepth_C = IndexOut;
  BufferEmpty <= IndexIn = IndexOut;

  BufferStatus_P : process(BufferStore)
  begin
    ReadsPending <= false;
    WritesPending <= false;

    for I in 0 to 2**Log2BufferDepth_C-1 loop
      case BufferStore(I).State is
        when LSOp_LoadSigned_C | LSOp_LoadUnSigned_C =>
          ReadsPending <= true;
          
        when LSOp_Store_C =>
          WritesPending <= true;

        when others =>        
          null;
      end case;
    end loop;
  end process;

  --
  -- Store data read
  --

  LS_ReadActive <=
    '1' when C_Operation = LSOp_Store_C
    else '1' when not BufferEmpty and BufferStore(IndexOut).State = LSOp_Store_C
    and BufferStore(IndexOut).Count > 0 else '0';
  
  LS_ReadIndex <=
    C_Dest when C_Operation = LSOp_Store_C
    else ( BufferStore(IndexOut).Dest + 1 ) mod 2**Log2NumOfRegs_C;
  
  --
  -- Status output
  --

  C_Ready <= '0' when BufferFull else '1';

  LoadsOutstanding <= '1' when ReadsPending or ReadsOutstanding else '0';

  StoresOutstanding <= '1' when WritesPending or WritesOutstanding else '0';

  --
  -- Work table storage
  --

  WorkTable_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        for I in 0 to 2**Log2TableSize_C-1 loop
          WorkTable(I) <= EmptyWorkEntry_C;
        end loop;
      else
        if not BufferEmpty and not WorkTableFull and LCI_Accept = '1' then
          -- Store an entry
          
          WorkTable(FreeIndex).State <= BufferStore(IndexOut).State;
          WorkTable(FreeIndex).Log2Size <= BufferStore(IndexOut).Log2Size;
          WorkTable(FreeIndex).Dest <= BufferStore(IndexOut).Dest;
          WorkTable(FreeIndex).Addr <= to_integer(unsigned(BufferStore(IndexOut).Addr(Log2BPW_C-1 downto 0)));
        end if;

        if SeeingValidResponse then
          -- We're completing a transaction
          WorkTable(ResponseIndex) <= EmptyWorkEntry_C;
        end if;       
      end if;
    end if;
  end process;
  
  --
  -- Work table state decode
  --

  DecodeTable_P : process(WorkTable)
  begin
    FreeIndex <= 0;
    WorkTableFull <= true;
    WritesOutstanding <= false;
    ReadsOutstanding <= false;
    
    for I in 2**Log2TableSize_C-1 downto 0 loop
      case WorkTable(I).State is
        when LSOp_None_C =>
          WorkTableFull <= false;
          FreeIndex <= I;

        when LSOp_Store_C =>
          WritesOutstanding <= true;
          
        when others =>
          ReadsOutstanding <= true;
      end case;
    end loop; 
  end process;

  --
  -- Outgoing initiative
  --

  LCI_Present <= '0' when BufferEmpty or WorkTableFull else '1';

  LCI_Write <= '1' when BufferStore(IndexOut).State = LSOp_Store_C else '0';

  LCI_Tag <= std_logic_vector(to_unsigned(FreeIndex, TagSize_C));

  LCI_Addr <= BufferStore(IndexOut).Addr(AddrSize_C-1 downto Log2BPW_C);

  SubwordWriteHandler_P : process(BufferStore, IndexOut, LS_ReadData)
    variable TempData : std_logic_vector(WordSize_C-1 downto 0);
    variable TempSel : std_logic_vector(2**Log2BPW_C-1 downto 0);
    constant ZeroByte_C : std_logic_vector(ByteSize_C-1 downto 0) := (others => '0');
  begin
    TempData := LS_ReadData; -- BufferStore(IndexOut).WriteData;
    TempSel := (others => '0');

    for I in 0 to 2**Log2BPW_C-1 loop
      if I < 2**BufferStore(IndexOut).Log2Size then
        TempSel(I) := '1';
      end if;
    end loop;

    for I in 0 to 2**Log2BPW_C-1 loop
      if I < to_integer(unsigned(BufferStore(IndexOut).Addr(Log2BPW_C-1 downto 0))) then
        TempData := TempData(WordSize_C-ByteSize_C-1 downto 0) & ZeroByte_C;
        TempSel := TempSel(2**Log2BPW_C-2 downto 0) & '0';
      end if;
    end loop;
    
    LCI_Data <= TempData;
    LCI_ByteSel <= TempSel;
  end process;
  
  --
  -- Incoming response interpretation
  --

  SeeingValidResponse <=
    LCR_Present = '1' and to_integer(unsigned(LCR_Tag(TagSize_C-1 downto Log2TableSize_C))) = 0
    and WorkTable(ResponseIndex).State /= LSOp_None_C;

  ResponseIndex <= to_integer(unsigned(LCR_Tag(Log2TableSize_C-1 downto 0)));

  ReadCompletion_P : process(Clk)
    variable TempData : std_logic_vector(WordSize_C-1 downto 0);
    variable FillByte : std_logic_vector(ByteSize_C-1 downto 0);
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        -- Being reset
        
        LS_WriteActive <= '0';
        LS_WriteIndex <= 0;
        LS_WriteData <= (others => '0');
        
      elsif SeeingValidResponse and WorkTable(ResponseIndex).State /= LSOp_Store_C then
        --
        -- We have a read response incoming
        --

        TempData := LCR_Data;
        FillByte := (others => '0');
            
        for I in 0 to 2**Log2BPW_C-1 loop
          if I < WorkTable(ResponseIndex).Addr then
            TempData := FillByte & TempData(WordSize_C-1 downto ByteSize_C);
          end if;
        end loop;

        if WorkTable(ResponseIndex).State = LSOp_LoadSigned_C then
          FillByte := (others => TempData(ByteSize_C*2**WorkTable(ResponseIndex).Log2Size - 1));
        end if;
        
        for I in 0 to 2**Log2BPW_C-1 loop
          if I >= 2**WorkTable(ResponseIndex).Log2Size then
            TempData((I+1)*ByteSize_C-1 downto I*ByteSize_C) := FillByte;
          end if;
        end loop;
    
        LS_WriteActive <= '1';
        LS_WriteIndex <= WorkTable(ResponseIndex).Dest;
        LS_WriteData <= TempData;
      else
        --
        -- Not completing a read
        --
        
        LS_WriteActive <= '0';        
        LS_WriteIndex <= 0;
        LS_WriteData <= (others => '0');        
      end if;
    end if;
  end process;
end RTL;
