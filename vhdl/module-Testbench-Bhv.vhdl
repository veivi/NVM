library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use std.textio.all;
use std.env.finish;

entity Testbench is
end Testbench;

architecture Bhv of Testbench is
  constant ClockCycle_C : time := 10 ns;
  constant Contention_C : real := 0.1;
  constant Log2IROMSize_C : integer := 10;
  constant Log2RAMSize_C : integer := 13;
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

  signal DebugOut : std_logic_vector(WordSize_C-1 downto 0);
  
  signal AVU_C_Present : std_logic;
  signal AVU_C_Accept : std_logic;
  signal AVU_C_Operation : std_logic_vector(ExtOpSize_C-1 downto 0);
  signal AVU_C_Tag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal AVU_C_OperandA : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  signal AVU_C_OperandB : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  signal AVU_C_OperandC : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

  -- Vector Unit Result

  signal AVU_R_Present : std_logic;
  signal AVU_R_Tag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal AVU_R_Result : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  
  subtype InstrWord_T is std_logic_vector(InstrSize_C-1 downto 0);
  type InstrArray_T is array (natural range <>) of InstrWord_T;

  impure function InitInstrStore(name : in string) return InstrArray_T is
    file file_pointer : text open read_mode is name;
    variable line_v : line;
    variable output : InstrArray_T(0 to 2**Log2IROMSize_C-1);
    variable i : integer := 0;
  begin
    while not endfile(file_pointer) loop
      readline(file_pointer, line_v);
      bread(line_v, output(i));
      i := i + 1;
    end loop;
    return output;
  end function;

  signal I_Store : InstrArray_T(0 to 2**Log2IROMSize_C-1) := InitInstrStore("i_rom.txt");
  
  signal Freeze : boolean := false;
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

             DebugOut => DebugOut,
             
             LCI_Present => LCI_Present,
             LCI_Accept => LCI_Accept,
             LCI_Write => LCI_Write,
             LCI_Tag => LCI_Tag,
             LCI_Addr => LCI_Addr,
             LCI_ByteSel => LCI_ByteSel,
             LCI_Data => LCI_Data,
             LCR_Present => LCR_Present,
             LCR_Tag => LCR_Tag,
             LCR_Data => LCR_Data,

             AVU_C_Present => AVU_C_Present,
             AVU_C_Accept => AVU_C_Accept,
             AVU_C_Operation => AVU_C_Operation ,
             AVU_C_Tag => AVU_C_Tag ,
             AVU_C_OperandA => AVU_C_OperandA ,
             AVU_C_OperandB => AVU_C_OperandB ,
             AVU_C_OperandC => AVU_C_OperandC ,
             AVU_R_Present => AVU_R_Present ,
             AVU_R_Tag => AVU_R_Tag ,
             AVU_R_Result => AVU_R_Result);

  --
  -- Vector Unit
  --
  
  VU102_I : entity WORK.VU102(RTL)
    generic map(Log2BPW_C => Log2BPW_C,
                Log2VecSIze_C => Log2VecSIze_C,
                Precision_C => 12)

    port map(Clk => Clk,
             Reset => Reset,
             
             AVU_C_Present => AVU_C_Present,
             AVU_C_Accept => AVU_C_Accept,
             AVU_C_Operation => AVU_C_Operation ,
             AVU_C_Tag => AVU_C_Tag ,
             AVU_C_OperandA => AVU_C_OperandA ,
             AVU_C_OperandB => AVU_C_OperandB ,
             AVU_C_OperandC => AVU_C_OperandC ,
             AVU_R_Present => AVU_R_Present ,
             AVU_R_Tag => AVU_R_Tag ,
             AVU_R_Result => AVU_R_Result);
  
  --
  -- Multi-Port Memory
  --

  MPM_I : entity WORK.MPM(Bhv)
    generic map(AddrSize_C => AddrSize_C - Log2BPW_C,
                Log2BPW_C => Log2BPW_C,
                TagSize_C => TagSize_C,
                NumOfPorts_C => 2**Log2VecSize_C + 1,
                Contention_C => Contention_C,
                Log2MemSize_C => Log2RAMSize_C )

    port map(Clk => Clk,
             Reset => Reset,
             DebugOut => DebugOut,
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
    Clk <= '1';
    wait for ClockCycle_C/2;
    Clk <= '0';
    wait for ClockCycle_C/2;

    if Freeze then
      report "Oscillator stop";
      finish;
      wait;
    end if;
  end process;

  --
  -- Reset circuit
  --

  Reset_P : process
  begin
    Reset <= '1';
    wait for 5*ClockCycle_C;
    Reset <= '0';
    wait;
  end process;

  --
  -- Instruction memory
  --

  I_Code <= I_Store(to_integer(unsigned(I_Addr(Log2IROMSize_C-1 downto 0)))) after 3 ns;      
  I_Ready <= '1';
  
  --
  -- Debug output monitor, stop the simulation if we see all '1's
  --

  Debug_P : process(Clk)
    variable timeStart : time;
    variable cycles : integer;
    variable Prev : std_logic_vector(WordSize_C-1 downto 0);
  begin
    if rising_edge(Clk) then
      if DebugOut = std_logic_vector(to_signed(-1, WordSize_C)) then
        report "Debug port stopping simulation";
        Freeze <= true;
      elsif DebugOut /= Prev then
        if DebugOut = std_logic_vector(to_unsigned(16#57A7#, WordSize_C)) then
          report "Time measurement STARTED";
          timeStart := now;
        elsif DebugOut = std_logic_vector(to_unsigned(16#570B#, WordSize_C)) then
          cycles := (now - timeStart) / ClockCycle_C;
          report "Time measurement STOPPED, duration = " & integer'image(cycles) & " cycles";
          timeStart := now;
        end if;

        Prev := DebugOut;
      end if;
    end if;
  end process;
end Bhv;
