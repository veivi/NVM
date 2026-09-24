--
--
--

package NVM101Interface is
  constant Log2ByteSize_C : integer := 3;
  
  constant ByteSize_C : integer := 2**Log2ByteSize_C;

  constant Log2MaxSpan_C : integer := 3;

  constant InstrSize_C : integer := 32;

  constant Log2MaxRegs_C : integer := 6;

  constant Log2NumOfCondRegs_C : integer := 2;

  constant ExtOpSize_C : integer := 8;
end package;

