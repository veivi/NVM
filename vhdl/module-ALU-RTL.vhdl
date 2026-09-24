library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity ALU is
  generic(Log2BPW_C : integer);
          
  port(Operation : in ALUOp_T;

       A : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       B : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Condition : out Condition_T);
end ALU;

architecture RTL of ALU is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;
begin
  process(Operation, A, B)
  begin
    -- Default result
    
    Condition <= Cond_Equal_C;
    Result <= (others => '0');
    
    case Operation is
      when ALUOp_OR_C =>
        Result <= A or B;

      when ALUOp_AND_C =>
        Result <= A and B;

      when ALUOp_XOR_C =>
        Result <= A xor B;

      when ALUOp_ADD_C =>
        Result <= std_logic_vector(unsigned(A) + unsigned(B));

      when ALUOp_SUB_C =>
        Result <= std_logic_vector(unsigned(A) - unsigned(B));

      when ALUOp_CMP_C =>
        if signed(A) > signed(B) then
          Condition <= Cond_GreaterThan_C;
        elsif signed(A) < signed(B) then
          Condition <= Cond_LessThan_C;
        end if;
        
      when ALUOp_CMPU_C =>
        if unsigned(A) > unsigned(B) then
          Condition <= Cond_GreaterThan_C;
        elsif unsigned(A) < unsigned(B) then
          Condition <= Cond_LessThan_C;
        end if;

      when ALUOp_LSL_C =>
        Result <= std_logic_vector(shift_left(unsigned(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            

      when ALUOp_LSR_C =>
        Result <= std_logic_vector(shift_right(unsigned(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            

      when ALUOp_ASR_C =>
        Result <= std_logic_vector(shift_right(signed(A),
                                              to_integer(unsigned(B(Log2ByteSize_C+Log2BPW_C-1 downto 0)))));
            
      when others =>
        null;
    end case; 
  end process;
end RTL;


       
