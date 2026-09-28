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
       IL_ExecuteStall : in std_logic;

       -- Decoded instruction input for decode and execute stages

       ControlWord : in ControlWord_T;
       ExecuteWord : in ControlWord_T;
       
       CR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Write_Active : in std_logic;
       CR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Write_Datum : in Datum_T;

       VCR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Read_Datum : out DatumVector_T(0 to 2**Log2VecSize_C-1);
       VCR_Write_Active : in std_logic;
       VCR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Write_Datum : in DatumVector_T(0 to 2**Log2VecSize_C-1);
       
       Imm_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Reg_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end FCU;

architecture RTL of FCU is
  signal NIP, FIP, DIP, LR : std_logic_vector(AddrSize_C-1 downto 0);

  subtype VectorDatum_T is DatumVector_T(0 to 2**Log2VecSize_C-1);
  
  type VectorDatumArray_T is array (natural range <>) of VectorDatum_T;
  
  signal CR : DatumVector_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal VCR : VectorDatumArray_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal Evaluated : std_logic;
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
        LR <= (others => '0');
      elsif IL_Stall = '0' then
        DIP <= FIP;
        FIP <= NIP;

        case ControlWord.FCU_Operation is
          when FlowOp_BCL_C =>
            if Evaluated = '1' then
              LR <= std_logic_vector(unsigned(FIP) + to_unsigned(1, AddrSize_C));
            end if;

          when FlowOp_JMPAL_C | FlowOp_JMPL_C =>
            LR <= std_logic_vector(unsigned(FIP) + to_unsigned(1, AddrSize_C));

          when others =>
            -- No linking
            null;            
        end case;
      else
      end if;
    end if;
  end process;

  --
  -- Next instruction pointer
  --

  NIP_P : process(FIP, DIP, LR, ControlWord, ExecuteWord, Evaluated, Imm_Data, Reg_Data)
  begin
    -- Default is to increment
    
    NIP <= std_logic_vector(unsigned(FIP) + to_unsigned(1, AddrSize_C));

    if ExecuteWord.FCU_Operation = FlowOp_JMP_C
      or ExecuteWord.FCU_Operation = FlowOp_JMPL_C then
      -- We're executing an indirect jump

      NIP <= Reg_Data(AddrSize_C-1 downto 0);

    else
      case ControlWord.FCU_Operation is
        when FlowOp_BC_C | FlowOp_BCL_C =>
          if Evaluated = '1' then
            -- Branch taken!
            NIP <= std_logic_vector(signed(DIP)
                                    + signed(Imm_Data(AddrSize_C-1 downto 0)));
          end if;

        when FlowOp_JMPA_C | FlowOp_JMPAL_C =>
          -- Absolute jump
          NIP <= Imm_Data(AddrSize_C-1 downto 0);

        when FlowOp_JMP_C | FlowOp_JMPL_C =>
          -- Indirect with displacement
        
          NIP <= std_logic_vector(signed(Reg_Data(AddrSize_C-1 downto 0))
                                  + signed(Imm_Data(AddrSize_C-1 downto 0)));

        when FlowOp_RET_C =>
          -- Return from subroutine

          NIP <= LR;
        
        when others =>
          null;
      end case;
    end if;
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
        CR <= (others => DefaultDatum_C);
      elsif IL_ExecuteStall = '0' and CR_Write_Active = '1' then
        CR(CR_Write_Index) <= CR_Write_Datum;
      end if;
    end if;
  end process;

  --
  -- Condition evaluation
  --

  Evaluate_P : process(ControlWord, CR, CR_Read_Index, CR_Write_Active, CR_Write_Index, CR_Write_Datum)
    variable Temp : Datum_T;
  begin
    Temp := CR(CR_Read_Index);

    if CR_Write_Active = '1' and CR_Write_Index = CR_Read_Index then
      -- Feedforward
      Temp := CR_Write_Datum;
    end if;
    
    case ControlWord.FCU_Predicate is
      when Pred_NE_C =>
        Evaluated <= Temp.LessThan or Temp.GreaterThan;
      when Pred_EQ_C =>
        Evaluated <= not (Temp.LessThan or Temp.GreaterThan);
      when Pred_LE_C =>
        Evaluated <= not Temp.GreaterThan;
      when Pred_LT_C =>
        Evaluated <= Temp.LessThan;
      when Pred_GE_C =>
        Evaluated <= not Temp.LessThan;
      when Pred_GT_C =>
        Evaluated <= Temp.GreaterThan;
      when others =>
        Evaluated <= '1';
    end case;
  end process;
  
  --
  -- Vector Condition register storage
  --

  VectorConditionStorage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        VCR <= (others => (others => DefaultDatum_C));
      elsif IL_ExecuteStall = '0' and VCR_Write_Active = '1' then
        VCR(VCR_Write_Index) <= VCR_Write_Datum;
      end if;
    end if;
  end process;

  VCR_Read_Datum <= VCR(VCR_Read_Index);
end RTL;
