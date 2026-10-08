library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.NVM101Interface.all;
use WORK.NVM101Types.all;
use WORK.SignalMath.all;

entity VU102 is
  generic(Log2BPW_C : integer;
          Log2VecSize_C : integer;
          Precision_C : integer);

  port(Clk : in std_logic;
       Reset : in std_logic;

       -- Vector Unit Command

       AVU_C_Present : in  std_logic;
       AVU_C_Accept : out std_logic;
       AVU_C_Operation : in std_logic_vector(ExtOpSize_C-1 downto 0);
       AVU_C_Tag : in std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_C_OperandA : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);
       AVU_C_OperandB : in std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0);

       -- Vector Unit Result

       AVU_R_Present : out std_logic;
       AVU_R_Tag : out std_logic_vector(Log2MaxRegs_C-1 downto 0);
       AVU_R_Result : out std_logic_vector(ByteSize_C*2**Log2BPW_C*2**Log2VecSize_C-1 downto 0));
end VU102;

architecture RTL of VU102 is
  constant WordSize_C : integer := ByteSize_C*2**Log2BPW_C;

  subtype Word_T is std_logic_vector(WordSize_C-1 downto 0);

  type WordArray_T is array (natural range <>) of Word_T;
  
  --
  -- Real/Imaginary part representation
  --
  
  constant PartSize_C : integer := WordSize_C/2;  
  constant IntSize_C : integer := PartSize_C - Precision_C;
  
  subtype Part_T is std_logic_vector(PartSize_C-1 downto 0);

  type PartialResult_T is record
    RealARealB : Word_T;
    ImagAImagB : Word_T;
    RealAImagB : Word_T;
    ImagARealB : Word_T;
  end record;

  type PartialResultArray_T is array (natural range <>) of PartialResult_T;
  
  function RealPart(A : Word_T) return Part_T is
  begin
    return A(WordSize_C-1 downto PartSize_C);
  end function;
  
  function ImagPart(A : Word_T) return Part_T is
  begin
    return A(PartSize_C-1 downto 0);
  end function;

  function Complex(RealPart : Part_T; ImagPart : Part_T) return Word_T is
  begin
    return RealPart & ImagPart;
  end function;

  function AddComplex(A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
  begin
    return Complex(Add(RealPart(A), RealPart(B)), Add(ImagPart(A), ImagPart(B)));
  end function;
  
  function Multiply(A : Part_T; B : Part_T) return Word_T is
  begin
    return std_logic_vector(signed(A) * signed(B));
  end function;

  function Normalize(A : Word_T) return Part_T is
    variable Temp : std_logic_vector(WordSize_C-1 downto 0);
  begin
    -- Round to nearest before truncating
    Temp := std_logic_vector(signed(A) + to_signed(2**(Precision_C-1), WordSize_C));
    -- Saturate
    Temp := Saturate(A, PartSize_C + Precision_C);
    -- Truncate
    return Temp(PartSize_C+Precision_C-1 downto Precision_C);
  end function;
  
  signal Operation : std_logic_vector(ExtOpSize_C-1 downto 0);
  signal PartialResult : PartialResultArray_T(0 to 2**Log2VecSize_C-1);
  signal AdderResult, MultiplyResult : WordArray_T(0 to 2**Log2VecSize_C-1);
  signal PartialValid, MultiplyValid : std_logic;
  signal PartialTag, MultiplyTag : std_logic_vector(Log2MaxRegs_C-1 downto 0);
  signal PartialOperation, MultiplyOperation : std_logic_vector(ExtOpSize_C-1 downto 0);
begin
  --
  -- Multiplication stage
  --

  Multiplier_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        PartialValid <= '0';
        Operation <= (others => '0');

      elsif AVU_C_Present = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          A := AVU_C_OperandA((I+1)*WordSize_C-1 downto I*WordSize_C);
          B := AVU_C_OperandB((I+1)*WordSize_C-1 downto I*WordSize_C);

          case to_integer(unsigned(AVU_C_Operation(2 downto 0))) is
            when 0 =>
              -- A * B
            
              PartialResult(I) <= (Multiply(RealPart(A), RealPart(B)), Multiply(ImagPart(A), ImagPart(B)),
                                   Multiply(RealPart(A), ImagPart(B)), Multiply(ImagPart(A), RealPart(B)));

            when 1 =>      
              -- A + B
            
              AdderResult(I) <= Complex(Add(RealPart(A), RealPart(B)),
                                        Add(ImagPart(A), ImagPart(B)));
              
            when 2 =>      
              -- A - B
            
              AdderResult(I) <= Complex(Add(RealPart(A), Negate(RealPart(B))),
                                        Add(ImagPart(A), Negate(ImagPart(B))));

            when 3 =>      
              -- A + iB
            
              AdderResult(I) <= Complex(Add(RealPart(A), Negate(ImagPart(B))),
                                        Add(ImagPart(A), RealPart(B)));
              
            when 4 =>      
              -- A - iB
            
              AdderResult(I) <= Complex(Add(RealPart(A), ImagPart(B)),
                                        Add(ImagPart(A), Negate(RealPart(B))));
              
            when others =>
              -- Invalid operation
              null;
          end case;
        end loop;

        PartialValid <= '1';
        PartialOperation <= AVU_C_Operation;        
        PartialTag <= AVU_C_Tag;
      else
        PartialValid <= '0';
        Operation <= (others => '0');
      end if;
    end if;
  end process;

  --
  -- Partial result adder
  --
  
  PartialAdder_P : process(Clk)
    variable A, B : Word_T;
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        MultiplyValid <= '0';

      elsif PartialValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          if PartialOperation(2 downto 0) = "000" then
            MultiplyResult(I) <= Complex(Normalize(Add(PartialResult(I).RealARealB,
                                                       Negate(PartialResult(I).ImagAImagB))),
                                         Normalize(Add(PartialResult(I).RealAImagB,
                                                       PartialResult(I).ImagARealB)));
          else
            MultiplyResult(I) <= AdderResult(I);
          end if;
        end loop;

        MultiplyTag <= PartialTag;
        MultiplyOperation <= PartialOperation;        
        MultiplyValid <= '1';
      else
        MultiplyValid <= '0';
        MultiplyOperation <= (others => '0');
      end if;
    end if;
  end process;

  --
  -- Accumulator/Result output
  --
  
  Accumulator_P : process(Clk)
  begin
    if rising_edge(Clk) then
      if Reset = '1' then
        AVU_R_Present <= '0';
        AVU_R_Tag <= (others => '0');

      elsif MultiplyValid = '1' then
        for I in 0 to 2**Log2VecSize_C-1 loop
          if MultiplyOperation(3) = '1' then
            -- Add the previous result to the result
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C)
              <= AddComplex(MultiplyResult(I), AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C));
          else
            -- Just output result of operation between A and B
            
            AVU_R_Result((I+1)*WordSize_C-1 downto I*WordSize_C) <= MultiplyResult(I);
          end if;
          AVU_R_Present <= '1';
          AVU_R_Tag <= MultiplyTag;
        end loop;
      else
        AVU_R_Present <= '0';
      end if;
    end if;
  end process;
  
  AVU_C_Accept <= '1';
end RTL;
