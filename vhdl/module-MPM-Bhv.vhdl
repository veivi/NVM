library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use WORK.NVM101Interface.all;
use std.textio.all;

entity MPM is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          TagSize_C : integer;
          NumOfPorts_C : integer;
          Contention_C : real;
          Log2MemSize_C : integer);
  
  port(Clk : in std_logic;
       Reset : in std_logic;

       --

       DebugOut : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       -- LCM initiative

       LCI_Present : in std_logic_vector(NumOfPorts_C-1 downto 0);
       LCI_Accept : out std_logic_vector(NumOfPorts_C-1 downto 0);
       LCI_Write : in std_logic_vector(NumOfPorts_C-1 downto 0);
       LCI_Tag : in std_logic_vector(TagSize_C*NumOfPorts_C-1 downto 0);
       LCI_Addr : in std_logic_vector(AddrSize_C*NumOfPorts_C-1 downto 0);
       LCI_ByteSel : in std_logic_vector(2**Log2BPW_C*NumOfPorts_C-1 downto 0);
       LCI_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C*NumOfPorts_C-1 downto 0);

       -- LCM response

       LCR_Present : out std_logic_vector(NumOfPorts_C-1 downto 0);
       LCR_Tag : out std_logic_vector(TagSize_C*NumOfPorts_C-1 downto 0);
       LCR_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C*NumOfPorts_C-1 downto 0));
end MPM;

architecture Bhv of MPM is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  
  constant ROMBase_C : integer := 2**(16 - Log2BPW_C);
    
  subtype Word_T is std_logic_vector(WordSize_C-1 downto 0);

  type WordArray_T is array (natural range <>) of Word_T;

  type State_T is ( Idle_C, Read_C, Write_C );

  type StateArray_T is array (natural range <>) of State_T;

  subtype Addr_T is integer;

  type AddrArray_T is array (natural range <>) of Addr_T;
  
  subtype Select_T is std_logic_vector(2**Log2BPW_C-1 downto 0);

  type SelectArray_T is array (natural range <>) of Select_T;
  
  subtype Tag_T is std_logic_vector(TagSize_C-1 downto 0);

  type TagArray_T is array (natural range <>) of Tag_T;
  
  impure function InitReadOnlyStore(name : in string) return WordArray_T is
    file file_pointer : text open read_mode is name;
    variable line_v : line;
    variable result : WordArray_T(0 to 2**Log2MemSize_C-1);
    variable i : integer := 0;
  begin
    while not endfile(file_pointer) loop
      readline(file_pointer, line_v);
      bread(line_v, result(i));
      --write(line_v, name);
      --write(line_v, string'(" ROM["));
      --hwrite(line_v, to_unsigned(i*4, AddrSize_C));
      --write(line_v, string'("]:="));             
      --hwrite(line_v, result(i));
      --writeline(output, line_v)
      i := i + 1;
    end loop;
    return result;
  end function;

  signal RAM : WordArray_T(0 to 2**Log2MemSize_C-1);
  signal ROM : WordArray_T(0 to 2**Log2MemSize_C-1) := InitReadOnlyStore("data_rom.txt");
  signal State : StateArray_T(0 to NumOfPorts_C-1);
  signal Addr : AddrArray_T(0 to NumOfPorts_C-1);
  
  signal ByteSel : SelectArray_T(0 to NumOfPorts_C-1);
  signal Tag : TagArray_T(0 to NumOfPorts_C-1);
  signal WriteData : WordArray_T(0 to NumOfPorts_C-1);
  signal PortReady : std_logic_vector(NumOfPorts_C-1 downto 0);
begin
  Control_P : process(Clk)
  begin
    if rising_edge(Clk) then
      for I in 0 to NumOfPorts_C-1 loop
        if LCI_Present(I) = '1' and PortReady(I) = '1' then
          if LCI_Write(I) = '1' then
            State(I) <= Write_C;
            WriteData(I) <= LCI_Data((I+1)*WordSize_C-1 downto I*WordSize_C);
          else
            State(I) <= Read_C;
          end if;

          Tag(I) <= LCI_Tag((I+1)*TagSize_C-1 downto I*TagSize_C);
          Addr(I) <= to_integer(unsigned(LCI_Addr((I+1)*AddrSize_C-1 downto I*AddrSize_C)));
          ByteSel(I) <= LCI_ByteSel((I+1)*2**Log2BPW_C-1 downto I*2**Log2BPW_C);
        else
          State(I) <= Idle_C;
        end if;
      end loop;       
    end if;
  end process;

  Storage_P : process(Clk)
    file file_pointer : text open write_mode is "MPM_report.txt";
    file log_file : text open write_mode is "log.txt";
    variable OutLine, DebugLine : line;
    variable Something : boolean;
    variable DebugState : Word_T := (others => '0');
    variable ReadData : Word_T;
  begin
    if rising_edge(Clk) then
      if DebugOut /= DebugState then
        write(OutLine, string'("------------------------------------------------------------------------------------------------------------------------------------------------"));
        writeline(file_pointer, Outline);
        write(OutLine, string'("-- DEBUG "));
        hwrite(OutLine, DebugOut);
        write(OutLine, string'(" at time "));
        write(OutLine, now);
        writeline(file_pointer, Outline);
        write(OutLine, string'("------------------------------------------------------------------------------------------------------------------------------------------------"));
        writeline(file_pointer, Outline);
        flush(file_pointer);
        DebugState := DebugOut;
      end if;

      Something := false;
      
      for P in 0 to NumOfPorts_C-1 loop
        if State(P) = Write_C then
          Something := true;
          
          if Addr(P) < 2**Log2MemSize_C then
            hwrite(OutLine, std_logic_vector(to_unsigned(Addr(P)*2**Log2BPW_C, AddrSize_C+Log2BPW_C)));
            write(OutLine, string'(":="));
          else
            hwrite(DebugLine, std_logic_vector(to_unsigned(Addr(P)*2**Log2BPW_C, AddrSize_C+Log2BPW_C)));
            write(DebugLine, string'(":="));
          end if;
          
          for I in 2**Log2BPW_C-1 downto 0 loop
            if ByteSel(P)(I) = '1' then
              hwrite(OutLine, WriteData(P)((I+1)*ByteSize_C-1 downto I*ByteSize_C));
              hwrite(DebugLine, WriteData(P)((I+1)*ByteSize_C-1 downto I*ByteSize_C));

              if Addr(P) < 2**Log2MemSize_C then
                RAM(Addr(P))((I+1)*ByteSize_C-1 downto I*ByteSize_C)
                  <= WriteData(P)((I+1)*ByteSize_C-1 downto I*ByteSize_C);
              end if; 
            else
              write(OutLine, string'("__"));
              write(DebugLine, string'("__"));
            end if;
          end loop;

          if Addr(P) >= 2**Log2MemSize_C then
            -- A write outside RAM, we log it separately
            if P < NumOfPorts_C-1 then
              write(DebugLine, string'(" (V"));
              write(DebugLine, P);
              write(DebugLine, string'(")"));
            else
              write(DebugLine, string'(" (S)"));
            end if;
            writeline(log_file, DebugLine);
          else
            deallocate(DebugLine);
          end if;
          
          write(OutLine, string'("|"));
          
        elsif State(P) = Read_C then
          Something := true;
          
          hwrite(OutLine, std_logic_vector(to_unsigned(Addr(P)*2**Log2BPW_C, AddrSize_C)));
          write(OutLine, string'(" ~"));
          
          if Addr(P) < ROMBase_C then
            ReadData := RAM(Addr(P));
          elsif Addr(P) < ROMBase_C + 2**Log2MemSize_C then
            ReadData := ROM(Addr(P) - ROMBase_C);
          else
            ReadData := (others => 'X');
          end if;
          
          for I in 2**Log2BPW_C-1 downto 0 loop
            if ByteSel(P)(I) = '1' then
              hwrite(OutLine, ReadData((I+1)*ByteSize_C-1 downto I*ByteSize_C));
            else
              write(OutLine, string'("__"));
            end if;
          end loop;

          write(OutLine, string'("|"));
        else
          write(OutLine, string'("               |"));
        end if;
      end loop;

      if Something then
        writeline(file_pointer, OutLine);
        flush(file_pointer);
      else
        deallocate(OutLine);
      end if;
    end if;
  end process;
  
  Responder_P : process(Clk)
    variable ReadData : Word_T;
  begin
    if rising_edge(Clk) then
      for P in 0 to NumOfPorts_C-1 loop
        if Reset = '1' or State(P) = Idle_C then
          LCR_Present(P) <= '0';
          LCR_Tag((P+1)*TagSize_C-1 downto P*TagSize_C) <= (others => '0');
          LCR_Data((P+1)*WordSize_C-1 downto P*WordSize_C) <= (others => '0');
        
        else
          LCR_Present(P) <= '1';
          LCR_Tag((P+1)*TagSize_C-1 downto P*TagSize_C) <= Tag(P);
          LCR_Data((P+1)*WordSize_C-1 downto P*WordSize_C) <= (others => 'X');

          if State(P) = Read_C then
            if Addr(P) < ROMBase_C then
              ReadData := RAM(Addr(P));
            elsif Addr(P) < ROMBase_C + 2**Log2MemSize_C then
              ReadData := ROM(Addr(P) - ROMBase_C);
            else
              ReadData := (others => 'X');
            end if;
          
            for I in 0 to 2**Log2BPW_C-1 loop
              if ByteSel(P)(I) = '1' then
                LCR_Data((P*2**Log2BPW_C+I+1)*ByteSize_C-1 downto (P*2**Log2BPW_C+I)*ByteSize_C)
                  <= ReadData((I+1)*ByteSize_C-1 downto I*ByteSize_C);
              end if;
            end loop;
          end if;
        end if;
      end loop;
    end if;
  end process;

  LCI_Accept <= PortReady;

  --
  -- Contention simulation
  --

  Contention_P : process(Clk)
    variable Seed1, Seed2 : positive;
    variable Rnd : real;
  begin
    if rising_edge(Clk) then
      for I in 0 to NumOfPorts_C-1 loop
        Uniform(Seed1, Seed2, Rnd);
        if Rnd < Contention_C then
          PortReady(I) <= '0';
        else
          PortReady(I) <= '1';
        end if;
      end loop;
    end if;
  end process;
end Bhv;

  
