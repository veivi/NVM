

package body NVM101Types is
  function DatumEvaluate(Datum : Datum_T; Pred : Predicate_T) return std_logic is
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
      when others =>
        return '1';
    end case;
  end function;
end package body;
