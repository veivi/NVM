library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use std.textio.all;

entity Testbench is
end Testbench;

architecture Bhv of Testbench is
  constant AddrSize_C : integer := 20;
  constant Log2BPW_C : integer := 2;
  constant WordAddrSize_C : integer := AddrSize_C - Log2BPW_C;
  constant BytesPerWord_C : integer := 2**Log2BPW_C;
  constant WordSize_C : integer := ByteSize_C*BytesPerWord_C;
  constant TagSize_C : integer := 8;
  constant Log2NumOfRegs_C : integer := 6;
  constant Log2VecSize_C : integer := 3;
  constant VecSize_C : integer := 2**Log2VecSize_C;
  signal Clk : std_logic;
  signal Reset : std_logic;

  signal I_Request : std_logic;
  signal I_Ready : std_logic;
  signal I_Addr : std_logic_vector(AddrSize_C-1 downto 0);
  signal I_Code : std_logic_vector(InstrSize_C-1 downto 0);

  signal LCI_Present : std_logic_vector(VecSize_C downto 0);
  signal LCI_Accept : std_logic_vector(VecSize_C downto 0);
  signal LCI_Write : std_logic_vector(VecSize_C downto 0);
  signal LCI_Tag : std_logic_vector(TagSize_C*(VecSize_C+1)-1 downto 0);
  signal LCI_Addr : std_logic_vector(WordAddrSize_C*(VecSize_C+1)-1 downto 0);
  signal LCI_ByteSel : std_logic_vector(2**Log2BPW_C*(VecSize_C+1)-1 downto 0);
  signal LCI_Data : std_logic_vector(ByteSize_C*2**Log2BPW_C*(VecSize_C+1)-1 downto 0);

  signal LCR_Present : std_logic_vector(VecSize_C downto 0);
  signal LCR_Tag : std_logic_vector(TagSize_C*(VecSize_C+1)-1 downto 0);
  signal LCR_Data : std_logic_vector(ByteSize_C*2**Log2BPW_C*(VecSize_C+1)-1 downto 0);

  subtype InstrWord_T is std_logic_vector(InstrSize_C-1 downto 0);
  type InstrArray_T is array (natural range <>) of InstrWord_T;

  impure function InitInstrStore(name : in string) return InstrArray_T is
        file file_pointer : text open read_mode is name;
        variable line_v : line;
        variable output : InstrArray_T(0 to 2**10-1);
        variable i : integer := 0;
    begin
        while not endfile(file_pointer) loop
          readline(file_pointer, line_v);
          bread(line_v, output(i));
          i := i + 1;
        end loop;
        return output;
    end function;

  signal I_Store : InstrArray_T(0 to 2**10-1) := InitInstrStore("i_rom.txt");
begin
  --
  -- Design Under Test
  --
  
  NVM101_I : entity WORK.NVM101(Struct)
    generic map(AddrSize_C => AddrSize_C,
                Log2BPW_C => Log2BPW_C,
                TagSize_C => TagSize_C,
                Log2NumOfRegs_C => Log2NumOfRegs_C,
                Log2VecSIze_C => Log2VecSIze_C )

    port map(Clk => Clk,
             Reset => Reset,
             I_Request => I_Request,
             I_Ready => I_Ready,
             I_Addr => I_Addr,
             I_Code => I_Code,

             LCI_Present => LCI_Present,
             LCI_Accept => LCI_Accept,
             LCI_Write => LCI_Write,
             LCI_Tag => LCI_Tag,
             LCI_Addr => LCI_Addr,
             LCI_ByteSel => LCI_ByteSel,
             LCI_Data => LCI_Data,
             LCR_Present => LCR_Present,
             LCR_Tag => LCR_Tag,
             LCR_Data => LCR_Data );

  --
  -- LCM
  --

  -- LCM_Generate : for I in 0 to 2**Log2VecSize_C generate
  --   LCM_I : entity WORK.LCM(Bhv)
  --     generic map(AddrSize_C => AddrSize_C - Log2BPW_C,
  --                 Log2BPW_C => Log2BPW_C,
  --                 TagSize_C => TagSize_C)

  --     port map(Clk => Clk,
  --              Reset => Reset,
  --              LCI_Present => LCI_Present(I),
  --              LCI_Accept => LCI_Accept(I),
  --              LCI_Write => LCI_Write(I),
  --              LCI_Tag => LCI_Tag((I+1)*TagSize_C-1 downto I*TagSize_C),
  --              LCI_Addr => LCI_Addr((I+1)*WordAddrSize_C-1 downto I*WordAddrSize_C),
  --              LCI_ByteSel => LCI_ByteSel((I+1)*BytesPerWord_C-1 downto I*BytesPerWord_C),
  --              LCI_Data => LCI_Data((I+1)*WordSize_C-1 downto I*WordSize_C),
  --              LCR_Present => LCR_Present(I),
  --              LCR_Tag => LCR_Tag((I+1)*TagSize_C-1 downto I*TagSize_C),
  --              LCR_Data => LCR_Data((I+1)*WordSize_C-1 downto I*WordSize_C));
  -- end generate;

  --
  -- Multi-Port Memory
  --

  MPM_I : entity WORK.MPM(Bhv)
    generic map(AddrSize_C => AddrSize_C - Log2BPW_C,
                Log2BPW_C => Log2BPW_C,
                TagSize_C => TagSize_C,
                NumOfPorts_C => 2**Log2VecSize_C + 1)

    port map(Clk => Clk,
             Reset => Reset,
             LCI_Present => LCI_Present,
             LCI_Accept => LCI_Accept,
             LCI_Write => LCI_Write,
             LCI_Tag => LCI_Tag,
             LCI_Addr => LCI_Addr,
             LCI_ByteSel => LCI_ByteSel,
             LCI_Data => LCI_Data,
             LCR_Present => LCR_Present,
             LCR_Tag => LCR_Tag,
             LCR_Data => LCR_Data);
    
  --
  -- Clock oscillator
  --

  Osc_P : process
  begin
    Clk <= '0';
    wait for 5 ns;
    Clk <= '1';
    wait for 5 ns;
  end process;

  --
  -- Reset circuit
  --

  Reset_P : process
  begin
    Reset <= '1';
    wait for 20 ns;
    Reset <= '0';
    wait;
  end process;

  --
  -- Instruction memory
  --

  I_Code <=
    I_Store(to_integer(unsigned(I_Addr))) after 3 ns when I_Request = '1' else (others => 'X');
  
  I_Ready <= '1';
end Bhv;
