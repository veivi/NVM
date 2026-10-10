library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity FCU is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          Log2VecSize_C : integer;
          Log2NumOfRegs_C : integer);

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

       -- Condition register interface
       
       CR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Read_Datum : out Datum_T;
       CR_Write_Active : in std_logic;
       CR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       CR_Write_Datum : in Datum_T;

       VCR_Read_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Read_Datum : out SimpleDatumVector_T(2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       VCR_Write_Active : in std_logic;
       VCR_Write_Index : in integer range 0 to 2**Log2NumOfCondRegs_C-1;
       VCR_Write_Datum : in SimpleDatumVector_T(2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       
       Imm_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Reg_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       Reg_Data_Out : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0));
end FCU;

architecture RTL of FCU is
  signal NIP, FIP, DIP, LR : std_logic_vector(AddrSize_C-1 downto 0);

  subtype VectorDatum_T is SimpleDatumVector_T(0 to 2**Log2BPW_C*2**Log2VecSize_C-1);
  
  type VectorDatumArray_T is array (natural range <>) of VectorDatum_T;

  signal CR : DatumVector_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal CR_Read_Value : Datum_T;
  signal VectorCR : VectorDatumArray_T(0 to 2**Log2NumOfCondRegs_C-1);
  signal Evaluated : std_logic;
  signal IDPointer : integer range 0 to 2**Log2IdRecordSize_C-1;
begin
  --
  -- Instruction pointer and link register storage
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

        if ExecuteWord.FCU_Operation = FlowOp_MvToSys_C
          and ExecuteWord.FCU_Index = System_LR_C then
          -- Move to Link Register

          LR <= Reg_Data(AddrSize_C-1 downto 0);
          
        else
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
        end if;
      else
      end if;
    end if;
  end process;

  --
  -- System register read decode
  --

  SystemRead_P : process(ExecuteWord, LR, IDPointer)
  begin
    case ExecuteWord.FCU_Index is
      when System_LR_C =>
        -- Link register value
        Reg_Data_Out <= std_logic_vector(resize(unsigned(LR), 2**Log2BPW_C*ByteSize_C));

      when System_ID_C =>
        -- ID register value
        case IDPointer is
          when 0 =>
            -- Magic number
            Reg_Data_Out <=
              std_logic_vector(to_unsigned(16#DEDBEEF#, 2**Log2BPW_C*ByteSize_C));

          when 1 =>
            -- Word size
            Reg_Data_Out <=
              std_logic_vector(to_unsigned(2**Log2BPW_C*ByteSize_C, 2**Log2BPW_C*ByteSize_C));
            
          when 2 =>
            -- Address size
            Reg_Data_Out <=
              std_logic_vector(to_unsigned(AddrSize_C, 2**Log2BPW_C*ByteSize_C));
            
          when 3 =>
            -- Vector size
            Reg_Data_Out <=
              std_logic_vector(to_unsigned(2**Log2VecSize_C, 2**Log2BPW_C*ByteSize_C));
            
          when 4 =>
            -- Num of registers
            Reg_Data_Out <=
              std_logic_vector(to_unsigned(2**Log2NumOfRegs_C, 2**Log2BPW_C*ByteSize_C));

          when others =>
            Reg_Data_Out <= 
              std_logic_vector(to_unsigned(16#B16B00B#, 2**Log2BPW_C*ByteSize_C));
        end case;

      when others =>
        Reg_Data_Out <= (others => '0');
        
    end case;
  end process;

  --
  -- ID Pointer
  --

  IDPointer_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        IDPointer <= 0;
        
      elsif ExecuteWord.FCU_Index = System_ID_C then
        if ExecuteWord.FCU_Operation = FlowOp_MvToSys_C then
          -- Write to ID register

          IDPointer <= to_integer(unsigned(Reg_Data(Log2IDRecordSize_C-1 downto 0)));
        elsif ExecuteWord.FCU_Operation = FlowOp_MvFrSys_C then
          -- Read from ID register

          IDPointer <= ( IDPointer + 1 ) mod 2**Log2IDRecordSize_C;
        end if;
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
  -- Condition read including feedforward
  --
  
  ConditionRead_P : process(CR, CR_Read_Index, CR_Write_Active, CR_Write_Index, CR_Write_Datum)
  begin
    CR_Read_Value <= CR(CR_Read_Index);
  
    if CR_Write_Active = '1' and CR_Write_Index = CR_Read_Index then
      -- Feedforward
      CR_Read_Value <= CR_Write_Datum;
    end if;
  end process;

  CR_Read_Datum <= CR_Read_Value;
  
  --
  -- Condition evaluation
  --

  Evaluated <= DatumEvaluate(CR_Read_Value, ControlWord.FCU_Predicate);
    
  --
  -- Vector Condition register storage
  --

  VectorConditionStorage_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        VectorCR <= (others => (others => DefaultSimpleDatum_C));
      elsif IL_ExecuteStall = '0' and VCR_Write_Active = '1' then
        VectorCR(VCR_Write_Index) <= VCR_Write_Datum;
      end if;
    end if;
  end process;

  VCR_Read_Datum <=
    VCR_Write_Datum when VCR_Write_Active = '1' and VCR_Write_Index = VCR_Read_Index
    else VectorCR(VCR_Read_Index);
end RTL;
