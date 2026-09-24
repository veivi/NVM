library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity VU101 is
  generic(Log2BPW_C : integer;
          Log2VecSize_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Vector Unit Command

       VectorC_Present : in  std_logic;
       VectorC_Accept : out std_logic;
       VectorC_Operation : in std_logic_vector(ExtOpSize_C-1 downto 0);
       VectorC_Dest : in std_logic_vector(Log2MaxRegs_C-1 downto 0);
       VectorC_OperandA : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       VectorC_OperandB : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       VectorC_OperandC : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

       -- Vector Unit Result

       VectorR_Present : out std_logic;
       VectorR_Dest : out std_logic_vector(Log2MaxRegs_C-1 downto 0);
       VectorR_Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0));
end VU101;

architecture RTL of VU101 is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  signal Operation : std_logic_vector(ExtOpSize_C-1 downto 0);
  signal OperandA : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  signal OperandB : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  signal OperandC : std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
  signal Dest : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal Busy, Complete : std_logic;  
begin
  --
  -- State
  --

  State_P : process(Clk)
    variable Count : integer := 0;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        Busy <= '0';
        Complete <= '0';
        Dest <= (others => '0');
        Operation <= (others => '0');
        
      elsif Busy = '1' then
        if Count > 10 then
          Complete <= '1';
          Busy <= '0';

          for I in 0 to 2**Log2VecSize_C-1 loop
            VectorR_Result((I+1)*WordSize_C-1 downto I*WordSize_C)
              <= std_logic_vector(unsigned(OperandA(I*WordSize_C+WordSize_C/2-1 downto I*WordSize_C))
                                  * unsigned(OperandB(I*WordSize_C+WordSize_C/2-1 downto I*WordSize_C)));
          end loop;
        else
          Count := Count + 1;
        end if;

      else
        Complete <= '0';
        
        if VectorC_Present = '1' then
          Busy <= '1';
          Dest <= VectorC_Dest;
          Operation <= VectorC_Operation;
          OperandA <= VectorC_OperandA;
          OperandB <= VectorC_OperandB;
          OperandC <= VectorC_OperandC;
          VectorR_Result <= (others => '0');
          Count := 0;
        end if;
      end if;
    end if;
  end process;
  
  VectorC_Accept <= not Busy;
  
  VectorR_Present <= Complete;
  VectorR_Dest <= Dest;
end RTL;
