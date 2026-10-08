library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use WORK.SignalMath.all;

entity VU101 is
  generic(Log2BPW_C : integer;
          Log2VecSize_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Vector Unit Command

       AVU_C_Present : in  std_logic;
       AVU_C_Accept : out std_logic;
       AVU_C_Operation : in std_logic_vector(ExtOpSize_C-1 downto 0);
       AVU_C_Tag : in std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_C_OperandA : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       AVU_C_OperandB : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

       -- Vector Unit Result

       AVU_R_Present : out std_logic;
       AVU_R_Tag : out std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_R_Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0));
end VU101;

architecture RTL of VU101 is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
  constant VecSize_C : integer := 2**Log2VecSize_C;
  constant BPW_C : integer := 2**Log2BPW_C;

  function ScaleByAlpha(A : std_logic_vector) return std_logic_vector is
  begin
    return std_logic_vector(shift_right(signed(A), 1) + shift_right(signed(A), 2));
  end function;
  
  signal Operation : std_logic_vector(ExtOpSize_C-1 downto 0);

  subtype Int8_t is std_logic_vector(ByteSize_C-1 downto 0);
  type Int8Array_t is array (natural range <>) of Int8_T;
  
  signal Min1, Min2, MinIndex : Int8Array_T(BPW_C*VecSize_C-1 downto 0);
  signal Sign, EdgeSign : std_logic_vector(BPW_C*VecSize_C-1 downto 0);
  signal Tag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal Busy : std_logic;  
  signal Index : integer range 0 to 2**ByteSize_C-1;
begin
  --
  -- State
  --

  State_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        Busy <= '0';
        Tag <= (others => '0');
        Operation <= (others => '0');
        Index <= 0;
        
      elsif AVU_C_Present = '1' then
        Busy <= '1';
        Tag <= AVU_C_Tag;

        case to_integer(unsigned(AVU_C_Operation)) is
          when 0 =>
            -- Initialize
            Min1 <= (others => std_logic_vector(to_signed(2**ByteSize_C/2-1, ByteSize_C)));
            Min2 <= (others => std_logic_vector(to_signed(2**ByteSize_C/2-1, ByteSize_C)));
            MinIndex <= (others => (others => '0'));
            Index <= 0;
            Sign <= (others => '0');

          when 1 =>
            -- Ingest edge
            for I in 0 to BPW_C*VecSize_C-1 loop
              if signed(Absolute(AVU_C_OperandA((I+1)*ByteSize_C-1 downto I*ByteSize_C)))
                < signed(Min1(I)) then
                Min2(I) <= Min1(I);              
                Min1(I) <= Absolute(AVU_C_OperandA((I+1)*ByteSize_C-1 downto I*ByteSize_C));
                MinIndex(I) <= std_logic_vector(to_unsigned(Index, ByteSize_C));
              elsif signed(Absolute(AVU_C_OperandA((I+1)*ByteSize_C-1 downto I*ByteSize_C)))
                < signed(Min2(I)) then
                Min2(I) <= Absolute(AVU_C_OperandA((I+1)*ByteSize_C-1 downto I*ByteSize_C));
              end if;

              Sign(I) <= Sign(I) xor AVU_C_OperandA((I+1)*ByteSize_C-1);
            end loop;

            Index <= Index + 1;

          when 2 =>
            -- Read edge
            if to_integer(unsigned(Operation)) /= 2 then
              Index <= 0;
            else
              Index <= Index + 1;
            end if;

            for I in 0 to BPW_C*VecSize_C-1 loop
              EdgeSign(I) <= AVU_C_OperandA((I+1)*ByteSize_C-1);
            end loop;
          when others =>
            null;
        end case;

        Operation <= AVU_C_Operation;
      else
        Busy <= '0';
      end if;
    end if;
  end process;
  
  AVU_C_Accept <= '1';
  
  AVU_R_Present <= Busy;
  AVU_R_Tag <= Tag;

  Response_P : process(Min1, Min2, MinIndex, Index, Sign, EdgeSign)
    variable LLR : Int8_T;
  begin
    for I in 0 to BPW_C*VecSize_C-1 loop
      if Index /= to_integer(unsigned(MinIndex(I))) then
        LLR := Min1(I);
      else
        LLR := Min2(I);
      end if;

      if (Sign(I) xor EdgeSign(I)) = '1' then
        LLR := Negate(LLR);
      end if;

      AVU_R_Result((I+1)*ByteSize_C-1 downto I*ByteSize_C) <= ScaleByAlpha(LLR);
    end loop;
  end process;
end RTL;
