library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity FCU is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          Log2VecSize_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Instruction interface

       I_Request : out std_logic;
       I_Ready : in std_logic;
       I_Addr : out std_logic_vector(AddrSize_C-1 downto 0);
       I_Code : in std_logic_vector(InstrSize_C-1 downto 0);

       -- Instruction output
       
       Instruction : out std_logic_vector(InstrSize_C-1 downto 0);

       -- Interlock interface
       
       IL_Stall : in std_logic;

       -- Decoded instruction input
       
       Operation : in FlowOp_T;
       
       CR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Write_Active : in std_logic;
       CR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Write_Data : in Condition_T;

       VCR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Read_Data : out ConditionVector_T(0 to 2**Log2VecSize_C-1);
       VCR_Write_Active : in std_logic;
       VCR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Write_Data : in ConditionVector_T(0 to 2**Log2VecSize_C-1);
       
       Imm_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Reg_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end FCU;

architecture RTL of FCU is
  signal NIP, FIP, DIP, XIP : std_logic_vector(AddrSize_C-1 downto 0);

  subtype VCRElem_T is ConditionVector_T(0 to 2**Log2VecSize_C-1);
  
  type VCRArray_T is array (natural range <>) of VCRElem_T;
  
  signal CR : ConditionVector_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal VCR : VCRArray_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal Evaluated : boolean;
begin
  --
  -- Instruction pointer storage
  --

  IP_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        -- Reset
        FIP <= (others => '0');
        DIP <= (others => '0');
        XIP <= (others => '0');
      elsif IL_Stall = '0' then
        XIP <= DIP;
        DIP <= FIP;
        FIP <= NIP;
      else
      end if;
    end if;
  end process;

  --
  -- Next instruction pointer
  --

  NIP_P : process(FIP, Operation, Evaluated)
  begin
    -- Default is to increment
    
    NIP <= std_logic_vector(unsigned(FIP) + to_unsigned(1, AddrSize_C));
    
    case Operation is
      when FlowOp_BNE_C | FlowOp_BEQ_C | FlowOp_BLE_C | FlowOp_BL_C 
        | FlowOp_BLT_C | FlowOp_BGE_C | FlowOp_BGT_C | FlowOp_BA_C =>
        if Evaluated then
          -- Branch taken!
          NIP <= std_logic_vector(unsigned(XIP)
                                  + unsigned(Imm_Data(AddrSize_C-1 downto 0)));
        end if;

      when FlowOp_JMPA_C | FlowOp_JMPAL_C =>
        -- Absolute jump
        NIP <= Imm_Data(AddrSize_C-1 downto 0);

      when FlowOp_JMP_C | FlowOp_JMPL_C =>
        -- Indirect jump
        NIP <= Reg_Data(AddrSize_C-1 downto 0);
        
      when others =>
        null;
    end case;
  end process;
  
  --
  -- Instruction interface
  --

  I_Addr <= FIP;
  I_Request <= not IL_Stall;

  IR_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        Instruction <= (others => '0');
      elsif IL_Stall = '0' then
        if I_Ready = '1' then
          Instruction <= I_Code;
        else
          Instruction <= (others => '0');
        end if;
      end if;
    end if;
  end process;
  
  --
  -- Condition register storage
  --

  ConditionStorage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        CR <= (others => Cond_Equal_C);
      elsif CR_Write_Active = '1' then
        CR(CR_Write_Index) <= CR_Write_Data;
      end if;
    end if;
  end process;

  --
  -- Condition evaluation
  --

  Evaluate_P : process(Operation, CR, CR_Read_Index)
  begin
    case Operation is
      when FlowOp_BNE_C =>
        Evaluated <= CR(CR_Read_Index) /= Cond_Equal_C;
      when FlowOp_BEQ_C =>
        Evaluated <= CR(CR_Read_Index) = Cond_Equal_C;
      when FlowOp_BLE_C =>
        Evaluated <= CR(CR_Read_Index) /= Cond_GreaterThan_C;
      when FlowOp_BLT_C =>
        Evaluated <= CR(CR_Read_Index) = Cond_LessThan_C;
      when FlowOp_BGE_C =>
        Evaluated <= CR(CR_Read_Index) /= Cond_LessThan_C;
      when FlowOp_BGT_C =>
        Evaluated <= CR(CR_Read_Index) = Cond_GreaterThan_C;
      when others =>
        Evaluated <= true;
    end case;
  end process;
  
  --
  -- Vector Condition register storage
  --

  VectorConditionStorage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        VCR <= (others => (others => Cond_Equal_C));
      elsif CR_Write_Active = '1' then
        VCR(CR_Write_Index) <= VCR_Write_Data;
      end if;
    end if;
  end process;

  VCR_Read_Data <= VCR(VCR_Read_Index);
end RTL;
