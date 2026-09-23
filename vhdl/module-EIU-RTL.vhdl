library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;

entity EIU is
  generic(Log2NumOfRegs_C : integer;
          Log2VecSize_C : integer);

  port(RF_Scoreboard : in std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
       VRF_Scoreboard : in std_logic_vector(2**Log2VecSize_C*2**Log2NumOfRegs_C-1 downto 0);
       RA_Active : in std_logic;
       RA_Index : in RegIndex_T;
       RB_Active : in std_logic;
       RB_Index : in  RegIndex_T;
       RC_Active : in std_logic;
       RC_Index : in  RegIndex_T;
       WA_Active : in std_logic;
       WA_Index : in  RegIndex_T;
       VRA_Active : in std_logic;
       VRA_Index : in RegIndex_T;
       VRB_Active : in std_logic;
       VRB_Index : in  RegIndex_T;
       VRC_Active : in std_logic;
       VRC_Index : in  RegIndex_T;
       VWA_Active : in std_logic;
       VWA_Index : in  RegIndex_T;
       Fence_Operation : in FenceOp_T;
       LoadsOutstanding : in std_logic;
       StoresOutstanding : in std_logic;       
       LS_Operation : in LoadStoreOp_T;
       LS_Ready : in std_logic;
       VLS_Operation : in LoadStoreOp_T;
       VLS_Ready : in std_logic_vector(2**Log2VecSize_C-1 downto 0);
       
       DecodeStall : out std_logic;
       ExecuteStall : out std_logic);
end EIU;

architecture RTL of EIU is
  signal RA_Stall : std_logic;
  signal RB_Stall : std_logic;
  signal RC_Stall : std_logic;
  signal WA_Stall : std_logic;
  signal VRA_Stall : std_logic;
  signal VRB_Stall : std_logic;
  signal VRC_Stall : std_logic;
  signal VWA_Stall : std_logic;
  signal LS_Stall : std_logic;
  signal VLS_Ready_All : std_logic;
  signal VLS_Stall : std_logic;
  signal Fence_Stall : std_logic;
  signal VRF_ScoreboardFolded : std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
begin
  --
  -- Scalar scoreboard decode
  --
  
  RA_Stall <= RF_Scoreboard(RA_Index) and RA_Active;
  RB_Stall <= RF_Scoreboard(RB_Index) and RB_Active;
  RC_Stall <= RF_Scoreboard(RC_Index) and RC_Active;
  WA_Stall <= RF_Scoreboard(WA_Index) and WA_Active;

  --
  -- Vector scoreboard decode
  --

  Fold_P : process(VRF_Scoreboard)
    variable Temp : std_logic_vector(2**Log2NumOfRegs_C-1 downto 0);
  begin
    Temp := (others => '0');
    
    for I in 0 to 2**Log2VecSize_C-1 loop
      Temp := Temp or VRF_Scoreboard((I+1)*2**Log2NumOfRegs_C-1 downto I*2**Log2NumOfRegs_C);
    end loop;

    VRF_ScoreboardFolded <= Temp;
  end process;
  
  VRA_Stall <= VRF_ScoreboardFolded(VRA_Index) and VRA_Active;
  VRB_Stall <= VRF_ScoreboardFolded(VRB_Index) and VRB_Active;
  VRC_Stall <= VRF_ScoreboardFolded(VRC_Index) and VRC_Active;
  VWA_Stall <= VRF_ScoreboardFolded(VWA_Index) and VWA_Active;

  --
  -- Scalar/vector LSU stall detection
  --
  
  LS_Stall <= not LS_Ready when LS_Operation /= LSOp_None_C else '0';

  VLS_P : process(VLS_Ready)
  begin
    VLS_Ready_All <= '1';
    
    for I in 0 to 2**Log2VecSize_C-1 loop
      if VLS_Ready(I) = '0' then
        VLS_Ready_All <= '0';
      end if;
    end loop;
  end process;
    
  VLS_Stall <= not VLS_Ready_All when VLS_Operation /= LSOp_None_C else '0';

  --
  -- Fence decode
  --

  Fence_P : process(Fence_Operation, LoadsOutstanding, StoresOutstanding)
  begin
    case Fence_Operation is
      when FenceOp_ReadFence_C =>
        Fence_Stall <= LoadsOutstanding;
        
      when FenceOp_WriteFence_C =>
        Fence_Stall <= StoresOutstanding;

      when FenceOp_Fence_C =>
        Fence_Stall <= StoresOutstanding or LoadsOutstanding;

      when others =>
        Fence_Stall <= '0';
    end case;
  end process;
  
  DecodeStall <= RA_Stall or RB_Stall or RC_Stall or WA_Stall
              or VRA_Stall or VRB_Stall or VRC_Stall or VWA_Stall;

  ExecuteStall <= LS_Stall or VLS_Stall or Fence_Stall;
end RTL;
