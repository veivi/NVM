library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity NVM101 is
  generic(AddrSize_C : integer;
          Log2BPW_C : integer;
          TagSize_C : integer;
          Log2NumOfRegs_C : integer;
          Log2VecSize_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Instruction interface

       I_Request : out std_logic;
       I_Ready : in std_logic;
       I_Addr : out std_logic_vector(AddrSize_C-1 downto 0);
       I_Code : in std_logic_vector(InstrSize_C-1 downto 0);

       -- Debug output

       DebugOut : out std_logic_vector(ByteSize_C*2**Log2BPW_C-1 downto 0);
       
       -- LCM initiative

       LCI_Present : out std_logic_vector(2**Log2VecSize_C downto 0);
       LCI_Accept : in std_logic_vector(2**Log2VecSize_C downto 0);
       LCI_Write : out std_logic_vector(2**Log2VecSize_C downto 0);
       LCI_Tag : out std_logic_vector(TagSize_C*(2**Log2VecSize_C+1)-1 downto 0);
       LCI_Addr : out std_logic_vector((AddrSize_C-Log2BPW_C)*(2**Log2VecSize_C+1)-1 downto 0);
       LCI_ByteSel : out std_logic_vector(2**Log2BPW_C*(2**Log2VecSize_C+1)-1 downto 0);
       LCI_Data : out std_logic_vector(ByteSize_C*2**Log2BPW_C*(2**Log2VecSize_C+1)-1 downto 0);

       -- LCM response

       LCR_Present : in std_logic_vector(2**Log2VecSize_C downto 0);
       LCR_Tag : in std_logic_vector(TagSize_C*(2**Log2VecSize_C+1)-1 downto 0);
       LCR_Data : in std_logic_vector(ByteSize_C*2**Log2BPW_C*(2**Log2VecSize_C+1)-1 downto 0);

       -- Application Vector Unit Command

       AVU_C_Present : out std_logic;
       AVU_C_Accept : in std_logic;
       AVU_C_Operation : out std_logic_vector(ExtOpSize_C-1 downto 0);
       AVU_C_Tag : out std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_C_OperandA : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       AVU_C_OperandB : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       AVU_C_OperandC : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

       -- Vector Unit Result

       AVU_R_Present : in std_logic;
       AVU_R_Tag : in std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_R_Result : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0));
end NVM101;

architecture Struct of NVM101 is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;

  constant WordAddrSize_C : integer := AddrSize_C - Log2BPW_C;
  
  constant VecSize_C : integer := 2**Log2VecSize_C;

  function LSOpIsLoad(Op : LoadStoreOp_T) return boolean is
  begin
    return Op = LSOp_LoadWord_C
      or Op = LSOp_LoadByteSigned_C or Op = LSOp_LoadByteUnsigned_C
      or Op = LSOp_LoadShortSigned_C or Op = LSOp_LoadShortUnsigned_C
      or Op = LSOp_LoadLongSigned_C or Op = LSOp_LoadLongUnsigned_C;
  end function;
  
  signal Instruction : std_logic_vector(InstrSize_C-1 downto 0);
  signal ControlWord : ControlWord_T;
  signal ExecuteWord : ControlWord_T;
  signal DecodeStall, ExecuteStall : std_logic;
  signal Stall : std_logic;
  
  signal Imm_Data, Execute_Imm_Data : std_logic_vector(WordSize_C-1 downto 0);
  
  signal LS_Ready : std_logic;
  signal LS_C_Stride : std_logic_vector(AddrSize_C-1 downto 0);
  
  signal LS_R_Present : std_logic;
  signal LS_R_Dest : RegIndex_T;
  signal LS_R_Data : std_logic_vector(WordSize_C-1 downto 0);
  
  signal RF_SB_Set : std_logic;
  signal RF_SB_Index : RegIndex_T;
  signal RF_SB_Span : RegSpan_T;
  signal RF_Scoreboard : std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
  signal RF_ReadValid : std_logic;
  signal RF_RA_Data : std_logic_vector(WordSize_C-1 downto 0);    
  signal RF_RB_Data : std_logic_vector(WordSize_C-1 downto 0);
  signal RF_RC_Data : std_logic_vector(WordSize_C-1 downto 0);
  signal RF_WA_Data : std_logic_vector(WordSize_C-1 downto 0);
  signal RF_WA_Valid : std_logic;

  signal ALU_Operation : ALUOp_T;
  signal ALU_Operand : std_logic_vector(WordSize_C-1 downto 0);
  signal ALU_Result : std_logic_vector(WordSize_C-1 downto 0);
  signal ALU_Condition : Condition_T;

  signal LoadsOutstanding, StoresOutstanding : std_logic;
  signal LS_LoadsOutstanding, LS_StoresOutstanding : std_logic;
  signal VLS_LoadsOutstanding, VLS_StoresOutstanding : std_logic_vector(VecSize_C-1 downto 0);
  
  signal VALU_Operation : ALUOp_T;
  signal VALU_OperandA : std_logic_vector(VecSize_C*WordSize_C-1 downto 0);
  signal VALU_OperandB : std_logic_vector(VecSize_C*WordSize_C-1 downto 0);
  signal VALU_Condition, VCR_ReadValue : ConditionVector_T(0 to VecSize_C-1);
  signal VALU_Result : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  
  signal VLS_Ready : std_logic_vector(VecSize_C-1 downto 0);
  signal VLS_C_Addr : std_logic_vector(VecSize_C*AddrSize_C-1 downto 0);
  signal VLS_C_Stride : std_logic_vector(AddrSize_C-1 downto 0);
  
  signal VLS_R_Present : std_logic_vector(VecSize_C-1 downto 0);
  signal VLS_R_Dest : RegIndexArray_T(0 to VecSize_C-1);
  signal VLS_R_Data : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  
  signal VRF_SB_Set : std_logic;
  signal VRF_SB_Index : RegIndex_T;
  signal VRF_SB_Span : RegSpan_T;
  signal VRF_Scoreboard : std_logic_vector(2**Log2NumOfRegs_C*VecSize_C-1 downto 0);
  signal VRF_ReadValid : std_logic_vector(VecSize_C-1 downto 0);
  signal VRF_WA_Active : std_logic;
  signal VRF_WA_Index : RegIndex_T;
  
  signal VRF_RA_Data : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  signal VRF_RB_Data : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  signal VRF_RC_Data : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  signal VRF_WA_Data : std_logic_vector(WordSize_C*VecSize_C-1 downto 0);
  signal VRF_WA_Valid : std_logic;
    
begin
  --
  -- Fetch and Control Unit
  --

  FCU_I : entity WORK.FCU(RTL)
    generic map(AddrSize_C => AddrSize_C,
                Log2BPW_C => Log2BPW_C,
                Log2VecSize_C => Log2VecSize_C)

    port map(Clk => Clk,
             Reset => Reset,
             I_Request => I_Request,
             I_Ready => I_Ready,
             I_Addr => I_Addr,
             I_Code => I_Code,

             Instruction => Instruction,
             Operation => ExecuteWord.FCU_Operation,

             IL_Stall => Stall,
             
             CR_Write_Active => ExecuteWord.CR_Write_Active,
             CR_Write_Index => ExecuteWord.CR_Write_Index,
             CR_Write_Data => ALU_Condition,
             CR_Read_Index => ExecuteWord.CR_Read_Index,
             
             VCR_Write_Active => ExecuteWord.VCR_Write_Active,
             VCR_Write_Index => ExecuteWord.VCR_Write_Index,
             VCR_Write_Data => VALU_Condition,
             VCR_Read_Index => ExecuteWord.VCR_Read_Index,
             VCR_Read_Data => VCR_ReadValue,
             
             Imm_Data => Execute_Imm_Data,
             Reg_Data => RF_RA_Data);
    
  --
  -- Debug port
  --

  Debug_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        DebugOut <= (others => '0');
        
      elsif ExecuteStall = '0' then
        case ExecuteWord.Debug_Operation is
          when DebugOp_DEBUGI_C =>
            DebugOut <= Execute_Imm_Data;
        
          when DebugOp_DEBUG_C =>
            DebugOut <= RF_RA_Data;

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;
  
  --
  -- Instruction Decode
  --

  IDU_I : entity WORK.IDU(Synthetic)
    generic map(Log2BPW_C => Log2BPW_C,
                Log2NumOfRegs_C => Log2NumOfRegs_C)

    port map(I_Code => Instruction,
             ControlWord => ControlWord,
             Imm_Data => Imm_Data);

  --
  -- Execution Interlock
  --

  EIU_I : entity WORK.EIU(RTL)
    generic map(Log2VecSize_C => Log2VecSize_C,
                Log2NumOfRegs_C => Log2NumOfRegs_C)

    port map(RF_Scoreboard => RF_Scoreboard,
             VRF_Scoreboard => VRF_Scoreboard,
             RA_Active => ControlWord.RF_RA_Active,
             RA_Index => ControlWord.RF_RA_Index,
             RB_Active => ControlWord.RF_RB_Active,
             RB_Index => ControlWord.RF_RB_Index,
             RC_Active => ControlWord.RF_RC_Active,
             RC_Index => ControlWord.RF_RC_Index,
             WA_Active =>ControlWord.RF_W_Active,
             WA_Index => ControlWord.RF_W_Index,
             VRA_Active => ControlWord.VRF_RA_Active,
             VRA_Index => ControlWord.VRF_RA_Index,
             VRB_Active => ControlWord.VRF_RB_Active,
             VRB_Index => ControlWord.VRF_RB_Index,
             VRC_Active => ControlWord.VRF_RC_Active,
             VRC_Index => ControlWord.VRF_RC_Index,
             VWA_Active =>ControlWord.VRF_W_Active,
             VWA_Index => ControlWord.VRF_W_Index,
             Fence_Operation => ExecuteWord.Fence_Operation,
             LoadsOutstanding => LoadsOutstanding,
             StoresOutstanding => StoresOutstanding,
             ALU_Operation => ExecuteWord.ALU_Operation,
             LS_Operation => ExecuteWord.LS_Operation,
             LS_Ready => LS_Ready,
             VLS_Operation => ExecuteWord.VLS_Operation,
             VLS_Ready => VLS_Ready,
             ExtC_Operation => ExecuteWord.Ext_Operation,
             ExtC_Accept => AVU_C_Accept,
             ExtR_Present => AVU_R_Present,
             DecodeStall => DecodeStall,
             ExecuteStall => ExecuteStall);

  Stall <= DecodeStall or ExecuteStall;
  
  --
  -- Scalar/Vector LSU fence combining
  --

  LoadsOutstanding <=
    '1' when to_integer(unsigned(VLS_LoadsOutstanding)) /= 0 else LS_LoadsOutstanding;
  
  StoresOutstanding <=
    '1' when to_integer(unsigned(VLS_StoresOutstanding)) /= 0 else LS_StoresOutstanding;
  
  --
  -- Control Word storage for execution stage
  --

  ExecuteWord_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        ExecuteWord <= DefaultControlWord_C;
        Execute_Imm_Data <= (others => '0');
        
      elsif ExecuteStall = '0' then
        -- We can proceed with execution
        
        if DecodeStall = '0' then
          -- Decode is cool, accept the new result
          ExecuteWord <= ControlWord;
          Execute_Imm_Data <= Imm_Data;
        else
          -- Decode has stalled, insert an execution bubble
          ExecuteWord <= DefaultControlWord_C;
        end if;
      end if;
    end if;
  end process;
  
  --
  -- Scalar LSU
  --

  LSU_I : entity WORK.VLSU(RTL)
    generic map(AddrSize_C => AddrSize_C,
                Log2BPW_C => Log2BPW_C,
                TagSize_C => TagSize_C,
                Log2TableSize_C => 4,
                Log2NumOfRegs_C => Log2NumOfRegs_C)

    port map(Clk => Clk,
             Reset => Reset,
             C_Operation => ExecuteWord.LS_Operation,
             C_Stall => ExecuteStall,
             C_Span => ExecuteWord.LS_Span,
             C_Ready => LS_Ready,               
             C_Dest => ExecuteWord.RF_RC_Index,
             C_Addr => ALU_Result(AddrSize_C-1 downto 0),
             C_Stride => LS_C_Stride,
             C_Data => RF_RC_Data,
             R_Present => LS_R_Present,
             R_Dest => LS_R_Dest,
             R_Data => LS_R_Data,
             LoadsOutstanding => LS_LoadsOutstanding,
             StoresOutstanding => LS_StoresOutstanding,
             LCI_Present => LCI_Present(VecSize_C),
             LCI_Accept => LCI_Accept(VecSize_C),
             LCI_Write => LCI_Write(VecSize_C),
             LCI_Tag => LCI_Tag((VecSize_C+1)*TagSize_C-1 downto VecSize_C*TagSize_C),
             LCI_Addr => LCI_Addr((VecSize_C+1)*WordAddrSize_C-1 downto VecSize_C*WordAddrSize_C),
             LCI_ByteSel => LCI_ByteSel((VecSize_C+1)*2**Log2BPW_C-1 downto VecSize_C*2**Log2BPW_C),
             LCI_Data => LCI_Data((VecSize_C+1)*WordSize_C-1 downto VecSize_C*WordSize_C),
             LCR_Present => LCR_Present(VecSize_C),
             LCR_Tag => LCR_Tag((VecSize_C+1)*TagSize_C-1 downto VecSize_C*TagSize_C),
             LCR_Data => LCR_Data((VecSize_C+1)*WordSize_C-1 downto VecSize_C*WordSize_C));

  LS_C_Stride <= (others => '0');
  
  --
  -- Scalar Register File
  --

  RFU_I : entity WORK.VRFU(RTL)
    generic map(Log2BPW_C => Log2BPW_C,
                Log2NumOfRegs_C => Log2NumOfRegs_C)

    port map(Clk => Clk,
             Reset => Reset,
             
             -- Scoreboard

             SB_Set => RF_SB_Set,
             SB_Index => RF_SB_Index,
             SB_Span => RF_SB_Span,
             Scoreboard => RF_Scoreboard,

             -- Interlock
             
             DecodeStall => DecodeStall,
             ExecuteStall => ExecuteStall,
             RF_ReadValid => RF_ReadValid,
             
             -- Read A

             RA_Active => ControlWord.RF_RA_Active,
             RA_Index => ControlWord.RF_RA_Index,
             RA_Data => RF_RA_Data,

             -- Read B

             RB_Active => ControlWord.RF_RB_Active,
             RB_Index => ControlWord.RF_RB_Index,
             RB_Data => RF_RB_Data,

             -- Read C

             RC_Active => ControlWord.RF_RC_Active,
             RC_Index => ControlWord.RF_RC_Index,
             RC_Data => RF_RC_Data,

             -- Write A, comes from either instruction decode (load immediate)
             -- or ALU

             WA_Active => ExecuteWord.RF_W_Active,
             WA_Valid => RF_WA_Valid,
             WA_Index => ExecuteWord.RF_W_Index,
             WA_Data => RF_WA_Data,
    
             -- Write B is used by the LSU load results
               
             WB_Active => LS_R_Present,
             WB_Index => LS_R_Dest,
             WB_Data => LS_R_Data);

  RF_WA_Valid <= RF_ReadValid;
  
  --
  -- Scalar scoreboard control
  --

  RF_SB_Set <= '1' when LSOpIsLoad(ControlWord.LS_Operation) else '0';
  RF_SB_Index <= ControlWord.RF_RC_Index;
  RF_SB_Span <= 0;
  
  --
  -- Scalar RF Write A Multiplexing
  --

  RF_WA_Data <= ALU_Result when ExecuteWord.ALU_Operation /= ALUOp_None_C else Execute_Imm_Data;
  
  --
  -- Scalar ALU
  --

  ALU_I : entity WORK.ALU(RTL)
    generic map(Log2BPW_C => Log2BPW_C)

    port map(Operation => ALU_Operation,
             A => RF_RA_Data,
             B => ALU_Operand,
             Result => ALU_Result,
             Condition => ALU_Condition);

  --
  -- ALU operation/operand multiplexing
  --

  ALUControl_P : process(ExecuteWord, Execute_Imm_Data, RF_RB_Data)
  begin
    -- Default operand comes from RFU
    
    ALU_Operation <= ExecuteWord.ALU_Operation;
    ALU_Operand <= RF_RB_Data;
    
    if ExecuteWord.LS_Operation /= LSOp_None_C then
      -- Override ALU operation for EA computation
      ALU_Operation <= ALUOp_Add_C;
      
      if ExecuteWord.LS_Mode = LS_Displaced_C then
        -- Immediate displacement
        ALU_Operand <= Execute_Imm_Data;
      end if;
      
    elsif ExecuteWord.ALU_Mode = ALU_RegImm_C then
      -- Possible ALU operation with immediate operand
      ALU_Operand <= Execute_Imm_Data;
    end if;
  end process ALUControl_P;
  
  --
  -- Vector Lane generator
  --

  VectorEngine_G : for I in 0 to VecSize_C-1 generate    
    --
    -- Load/Store Unit
    --
    
    VLSU_I : entity WORK.VLSU(RTL)
      generic map(AddrSize_C => AddrSize_C,
                  Log2BPW_C => Log2BPW_C,
                  TagSize_C => TagSize_C,
                  Log2TableSize_C => 4,
                  Log2NumOfRegs_C => Log2NumOfRegs_C)

      port map(Clk => Clk,
               Reset => Reset,
               C_Operation => ExecuteWord.VLS_Operation,
               C_Stall => ExecuteStall,
               C_Span => ExecuteWord.VLS_Span,
               C_Ready => VLS_Ready(I),               
               C_Dest => ExecuteWord.VRF_RC_Index,
               C_Addr => VALU_Result(I*WordSize_C+AddrSize_C-1 downto I*WordSize_C),
               C_Stride => VLS_C_Stride,
               C_Data => VRF_RC_Data((I+1)*WordSize_C-1 downto I*WordSize_C),
               LoadsOutstanding => VLS_LoadsOutstanding(I),
               StoresOutstanding => VLS_StoresOutstanding(I),
               R_Present => VLS_R_Present(I),
               R_Dest => VLS_R_Dest(I),
               R_Data => VLS_R_Data((I+1)*WordSize_C-1 downto I*WordSize_C),
               LCI_Present => LCI_Present(I),
               LCI_Accept => LCI_Accept(I),
               LCI_Write => LCI_Write(I),
               LCI_Tag => LCI_Tag((I+1)*TagSize_C-1 downto I*TagSize_C),
               LCI_Addr => LCI_Addr((I+1)*WordAddrSize_C-1 downto I*WordAddrSize_C),
               LCI_ByteSel => LCI_ByteSel((I+1)*2**Log2BPW_C-1 downto I*2**Log2BPW_C),
               LCI_Data => LCI_Data((I+1)*WordSize_C-1 downto I*WordSize_C),
               LCR_Present => LCR_Present(I),
               LCR_Tag => LCR_Tag((I+1)*TagSize_C-1 downto I*TagSize_C),
               LCR_Data => LCR_Data((I+1)*WordSize_C-1 downto I*WordSize_C));

    --
    -- Register File
    --
    
    VRFU_I : entity WORK.VRFU(RTL)
      generic map(Log2BPW_C => Log2BPW_C,
                  Log2NumOfRegs_C => Log2NumOfRegs_C)

      port map(Clk => Clk,
               Reset => Reset,

               -- Scoreboard

               SB_Set => VRF_SB_Set,
               SB_Index => VRF_SB_Index,
               SB_Span => VRF_SB_Span,
               Scoreboard => VRF_Scoreboard((I+1)*2**Log2NumOfRegs_C-1 downto I*2**Log2NumOfRegs_C),
               
               DecodeStall => DecodeStall,
               ExecuteStall => ExecuteStall,
               RF_ReadValid => VRF_ReadValid(I),
             
               -- Read A

               RA_Active => ControlWord.VRF_RA_Active,
               RA_Index => ControlWord.VRF_RA_Index,
               RA_Data => VRF_RA_Data((I+1)*WordSize_C-1 downto I*WordSize_C),

               -- Read B

               RB_Active => ControlWord.VRF_RB_Active,
               RB_Index => ControlWord.VRF_RB_Index,
               RB_Data => VRF_RB_Data((I+1)*WordSize_C-1 downto I*WordSize_C),

               -- Read C

               RC_Active => ControlWord.VRF_RC_Active,
               RC_Index => ControlWord.VRF_RC_Index,
               RC_Data => VRF_RC_Data((I+1)*WordSize_C-1 downto I*WordSize_C),

               -- Write A
               
               WA_Active => VRF_WA_Active,
               WA_Valid => VRF_WA_Valid,
               WA_Index => VRF_WA_Index,
               WA_Data => VRF_WA_Data((I+1)*WordSize_C-1 downto I*WordSize_C),
    
               -- Write B is used by the VLSU load results
               
               WB_Active => VLS_R_Present(I),
               WB_Index => VLS_R_Dest(I),
               WB_Data => VLS_R_Data((I+1)*WordSize_C-1 downto I*WordSize_C));

    --
    -- Integer ALU
    --

    VALU_I : entity WORK.ALU(RTL)
      generic map(Log2BPW_C => Log2BPW_C)

      port map(Operation => VALU_Operation,
               A => VALU_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C),
               B => VALU_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C),
               Result => VALU_Result((I+1)*WordSize_C-1 downto I*WordSize_C),
               Condition => VALU_Condition(I));
    
  end generate;

  --
  -- VRF write port multiplexing (vector integer ALU and Vector Extension share it, the
  -- latter has priority)
  --
  
  VRF_WA_Active <= ExecuteWord.VRF_W_Active or AVU_R_Present;
  VRF_WA_Valid <=  AVU_R_Present when to_integer(unsigned(not VRF_ReadValid)) /= 0 else '1';
  VRF_WA_Index <= to_integer(unsigned(AVU_R_Tag)) when AVU_R_Present = '1' else ExecuteWord.VRF_W_Index;
  VRF_WA_Data <= AVU_R_Result when AVU_R_Present = '1' else VALU_Result;
  
  --
  -- Vector ALU operation/operand multiplexing
  --

  VectorALUControl_P : process(ExecuteWord, Execute_Imm_Data, RF_RA_Data, RF_RB_Data, VRF_RA_Data, VRF_RB_Data)
    constant StubSize_C : integer := AddrSize_C - Log2VecSize_C;
    variable Stride : std_logic_vector(StubSize_C-1 downto 0);
  begin
    -- Default: vector ALUs are under instruction control and operands come from VRFU
    
    VALU_Operation <= ExecuteWord.VALU_Operation;
    VALU_OperandA <= VRF_RA_Data;
    VALU_OperandB <= VRF_RB_Data;

    -- The stride can come from scalar RF_B or instruction word
    
    Stride :=
      Execute_Imm_Data(StubSize_C-1 downto 0) when ExecuteWord.VLS_Mode = VLS_Imm_C
      else RF_RB_Data(StubSize_C-1 downto 0);
    
    if ExecuteWord.VLS_Operation /= LSOp_None_C then
      -- Override ALU operation for EA computation. Operand A is broadcast from
      -- scalar RFU, operand B is calculated per lane as stride multiples
      
      VALU_Operation <= ALUOp_Add_C;
      
      for I in 0 to VecSize_C-1 loop
        VALU_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C)
          <= RF_RA_Data;
        VALU_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C)
          <= std_logic_vector(to_unsigned(I, WordSize_C-AddrSize_C+Log2VecSize_C)*unsigned(Stride));
      end loop;

    elsif ExecuteWord.RF_RB_Active = '1' then
      -- Broadcast the scalar register to the vector lanes

      for I in 0 to VecSize_C-1 loop
        VALU_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C) <= RF_RB_Data;
      end loop;
      
    elsif ExecuteWord.VALU_Mode = ALU_RegImm_C then
      -- Possible vector ALU operation with immediate operand
      for I in 0 to VecSize_C-1 loop
        VALU_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C) <= Execute_Imm_Data;
      end loop;
    end if;
  end process;
  
  --
  -- Vector scoreboard control
  --

  VRF_SB_Set <= '1' when LSOpIsLoad(ControlWord.VLS_Operation) or ControlWord.Ext_Active = '1' else '0';
  VRF_SB_Index <= ControlWord.Ext_Dest when ControlWord.Ext_Active = '1' else ControlWord.VRF_RC_Index;
  VRF_SB_Span <= 0;

  --
  -- Vector Extension Interface
  --

  AVU_C_Present <= ExecuteWord.Ext_Active;
  AVU_C_Operation <= std_logic_vector(to_unsigned(ExecuteWord.Ext_Operation, ExtOpSize_C));
  AVU_C_Tag <= std_logic_vector(to_unsigned(ExecuteWord.Ext_Dest, Log2MaxRegs_C));
  AVU_C_OperandA <= VRF_RA_Data;
  AVU_C_OperandB <= VRF_RB_Data;
  AVU_C_OperandC <= VRF_RC_Data;
end Struct;


       
