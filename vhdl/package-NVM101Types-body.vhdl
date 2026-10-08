library IEEE;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;

package body NVM101Types is
  function PredicateDecode(Pred : std_logic_vector) return Predicate_T is
  begin
    case to_integer(unsigned(Pred)) is
      when EncodedPred_NE_C =>
        return Pred_NE_C;
        
      when EncodedPred_EQ_C =>
        return Pred_EQ_C;
        
      when EncodedPred_LT_C =>
        return Pred_LT_C;
        
      when EncodedPred_LE_C =>
        return Pred_LE_C;
        
      when EncodedPred_GT_C  =>
        return Pred_GT_C;
        
      when EncodedPred_GE_C =>
        return Pred_GE_C;
        
      when EncodedPred_CS_C =>
        return Pred_CS_C;
        
      when EncodedPred_CC_C =>
        return Pred_CC_C;
        
      when EncodedPred_OVF_C =>
        return Pred_OVF_C;        

      when others =>
        return Pred_A_C;
    end case;
  end function;
  
  function DatumEvaluate(Datum : SimpleDatum_T; Pred : Predicate_T) return std_logic is
  begin
    case Pred is
      when Pred_NE_C =>
        return Datum.LessThan or Datum.GreaterThan;
      when Pred_EQ_C =>
        return not (Datum.LessThan or Datum.GreaterThan);
      when Pred_LE_C =>
        return not Datum.GreaterThan;
      when Pred_LT_C =>
        return Datum.LessThan;
      when Pred_GE_C =>
        return not Datum.LessThan;
      when Pred_GT_C =>
        return Datum.GreaterThan;
      when Pred_A_C =>
        return '1';
      when others =>
        return '0';
    end case;
  end function;

  function DatumEvaluate(Datum : Datum_T; Pred : Predicate_T) return std_logic is
  begin
    case Pred is
      when Pred_CS_C =>
        return Datum.Carry;
        
      when Pred_CC_C =>
        return not Datum.Carry;
        
      when Pred_OVF_C =>
        return Datum.Overflow;

      when others =>
        return DatumEvaluate(Datum.Compare, Pred);
    end case;
  end function;

  function LSOpIsLoad(Op : LoadStoreOp_T) return boolean is
  begin
    return Op = LSOp_LoadSigned_C or Op = LSOp_LoadUnsigned_C;
  end function;
end package body;
