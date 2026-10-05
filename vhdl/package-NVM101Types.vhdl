--
--
--

library IEEE;
use IEEE.std_logic_1164.all;
use WORK.NVM101Interface.all;

package NVM101Types is
  type ALUOp_T is ( ALUOp_None_C,
                    ALUOp_OR_C,
                    ALUOp_AND_C,
                    ALUOp_XOR_C,
                    ALUOp_NOR_C,
                    ALUOp_ADD_C,
                    ALUOp_SUB_C,
                    ALUOp_LSR_C,
                    ALUOp_LSL_C,
                    ALUOp_ASR_C,
                    ALUOp_CMP_C,
                    ALUOp_CMPU_C,
                    ALUOp_CMP8_C,
                    ALUOp_CMP16_C,
                    ALUOp_ROTC_C,
                    ALUOp_ADDRI_C,
                    ALUOp_ADDRNI_C,
                    ALUOp_ABS_C,
                    ALUOp_ADD8_C,
                    ALUOp_SUB8_C,
                    ALUOp_ABS8_C,
                    ALUOp_NEG8_C,
                    ALUOp_ADD16_C,
                    ALUOp_SUB16_C,
                    ALUOp_ABS16_C,
                    ALUOp_NEG16_C );

  type ALUMode_T is ( ALU_RegReg_C, ALU_RegImm_C );

  type Predicate_T is ( Pred_EQ_C,
                        Pred_NE_C,
                        Pred_LT_C,
                        Pred_LE_C,
                        Pred_GT_C,
                        Pred_GE_C,
                        Pred_A_C,
                        Pred_CS_C,
                        Pred_CC_C,
                        Pred_OVF_C );

  function PredicateDecode(Pred : std_logic_vector) return Predicate_T;
  
  type Datum_T is record
    LessThan : std_logic;
    GreaterThan : std_logic;
    Carry : std_logic;
    Overflow : std_logic;
  end record;

  constant DefaultDatum_C : Datum_T := (others => '0');
  
  type DatumVector_T is array (natural range <>) of Datum_T;
  
  function DatumEvaluate(Datum : Datum_T; Pred : Predicate_T) return std_logic;
  
  type LoadStoreOp_T is ( LSOp_None_C,
                          LSOp_LoadSigned_C,
                          LSOp_LoadUnsigned_C,
                          LSOp_Store_C,
                          LSOp_Sync_C );

  function LSOpIsLoad(Op : LoadStoreOp_T) return boolean;
  
  constant Log2MaxSize_C : integer := 3;
  
  subtype SizeSpec_T is integer range 0 to 2**Log2MaxSize_C-1;
  
  type LoadStoreSize_T is ( LS_Byte_C,
                            LS_Short_C,
                            LS_Long_C,
                            LS_Word_C );

  type LoadStoreMode_T is ( LS_Displaced_C,
                            LS_Indexed_C );
  
  type VectorLoadStoreMode_T is ( VLS_Imm_C,
                                  VLS_Reg_C );

  type FlowOp_T is ( FlowOp_None_C,
                     FlowOp_BC_C,
                     FlowOp_BCL_C,
                     FlowOp_JMP_C,
                     FlowOp_JMPL_C,
                     FlowOp_JMPA_C,
                     FlowOp_JMPAL_C,
                     FlowOp_RET_C );
 
  type DebugOp_T is ( DebugOp_None_C,
                      DebugOp_DEBUG_C,
                      DebugOp_DEBUGI_C);
  
  type FenceOp_T is ( FenceOp_None_C,
                      FenceOp_Fence_C,
                      FenceOp_ReadFence_C,
                      FenceOp_WriteFence_C);
    
  type ImmOp_T is ( ImmOp_None_C,
                    ImmOp_Load_C );

  subtype RegIndex_T is integer range 0 to 2**Log2MaxRegs_C-1;
  
  type RegIndexArray_T is array (natural range <>) of RegIndex_T;
  
  subtype RegSpan_T is integer range 0 to 2**Log2MaxSpan_C-1;
  
  subtype CondRegIndex_T is integer range 0 to 2**Log2NumOfCondRegs_C-1;
  
  type ControlWord_T is record
    RF_RA_Active : std_logic;
    RF_RA_Index : RegIndex_T;
    RF_RB_Active : std_logic;
    RF_RB_Index : RegIndex_T;
    RF_RC_Active : std_logic;
    RF_RC_Index : RegIndex_T;
    RF_W_Active : std_logic;
    RF_W_Index : RegIndex_T;
    VRF_RA_Active : std_logic;
    VRF_RA_Index : RegIndex_T;
    VRF_RB_Active : std_logic;
    VRF_RB_Index : RegIndex_T;
    VRF_RC_Active : std_logic;
    VRF_RC_Index : RegIndex_T;
    VRF_W_Active : std_logic;
    VRF_W_Index : RegIndex_T;
    CR_Read_Active : std_logic;
    CR_Read_Index : CondRegIndex_T;
    CR_Write_Active : std_logic;
    CR_Write_Index : CondRegIndex_T;
    VCR_Read_Active : std_logic;
    VCR_Read_Index : CondRegIndex_T;
    VCR_Write_Active : std_logic;
    VCR_Write_Index : CondRegIndex_T;
    FCU_Operation : FlowOp_T;
    FCU_Predicate : Predicate_T;
    Debug_Operation : DebugOp_T;
    LS_Operation : LoadStoreOp_T;
    LS_Target : RegIndex_T;
    LS_Log2Size : SizeSpec_T;
    LS_Mode : LoadStoreMode_T;
    LS_Span : RegSpan_T;
    VLS_Operation : LoadStoreOp_T;
    VLS_Target : RegIndex_T;
    VLS_Log2Size : SizeSpec_T;
    VLS_Mode : VectorLoadStoreMode_T;
    VLS_Span : RegSpan_T;
    ALU_Operation : ALUOp_T;
    ALU_Predicate : Predicate_T;
    ALU_Mode : ALUMode_T;
    VALU_Operation : ALUOp_T;
    VALU_Predicate : Predicate_T;
    VALU_Mode : ALUMode_T;
    Imm_Operation : ImmOp_T;
    Fence_Operation : FenceOp_T;
    Ext_Active : std_logic;
    Ext_Operation : integer range 0 to 2**ExtOpSize_C-1;
    Ext_Dest : RegIndex_T;
  end record;

  constant DefaultControlWord_C : ControlWord_T :=
    ( '0', 0, '0', 0, '0', 0, '0', 0,
      '0', 0, '0', 0, '0', 0, '0', 0,
      '0', 0, '0', 0,
      '0', 0, '0', 0,
      FlowOp_None_C, Pred_A_C, DebugOp_None_C,
      LSOp_None_C, 0, 0, LS_Displaced_C, 0,
      LSOp_None_C, 0, 0, VLS_Imm_C, 0,
      ALUOp_None_C, Pred_A_C, ALU_RegReg_C, ALUOp_None_C, Pred_A_C, ALU_RegReg_C, ImmOp_None_C, FenceOp_None_C,
      '0', 0, 0);
end package;

