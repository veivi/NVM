--
--
--

package NVM101Interface is
  constant Log2ByteSize_C : integer := 3;
  
  constant ByteSize_C : integer := 2**Log2ByteSize_C;

  constant SpanSpecSize_C : integer := 2;

  constant InstrSize_C : integer := 32;

  constant Log2MaxRegs_C : integer := 6;

  constant Log2NumOfCondRegs_C : integer := 2;

  constant Log2MaxSize_C : integer := 3;
  
  constant ExtOpSize_C : integer := 8;

  --
  -- Encoded predicate
  --
  
  constant EncodedPred_A_C : integer := 0;
  constant EncodedPred_NE_C : integer := 1;
  constant EncodedPred_EQ_C : integer := 2;
  constant EncodedPred_LT_C : integer := 3;
  constant EncodedPred_LE_C : integer := 4;
  constant EncodedPred_GT_C : integer := 5;
  constant EncodedPred_GE_C : integer := 6;
  constant EncodedPred_CS_C : integer := 7;
  constant EncodedPred_CC_C : integer := 8;
  constant EncodedPred_OVF_C : integer := 9;

  --
  -- System register definitions
  --

  constant Log2IDRecordSize_C : integer := 3;
  
  constant System_ID_C : integer := 0;
  constant System_LR_C : integer := 1;  
end package;

