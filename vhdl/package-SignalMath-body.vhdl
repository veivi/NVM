library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package body SignalMath is
  function Saturate(A : std_logic_vector; W : natural) return std_logic_vector is
    constant Len_C : integer := A'range'high - A'range'low + 1;
    variable MinValue, MaxValue, Temp : signed(A'range);
  begin
    MinValue := (others => '0');
    MinValue(Len_C-1 downto W-1) := (others => '1');
    
    MaxValue := (others => '1');
    MaxValue(Len_C-1 downto W-1) := (others => '0');
    
    Temp := signed(A);
    
    if Temp < MinValue then
      Temp := MinValue;
    elsif Temp > MaxValue then
      Temp := MaxValue;
    end if;
    
    return std_logic_vector(Temp);
  end function;

  function Add(A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
    constant W : integer := A'range'high - A'range'low + 2;
    variable Temp : signed(W-1 downto 0);
  begin
    Temp := resize(signed(A), W) + resize(signed(B), W);
    Temp := signed(Saturate(std_logic_vector(Temp), W-1));
    return std_logic_vector(Temp(W-2 downto 0));
  end function;

  function Negate(A : std_logic_vector) return std_logic_vector is
    constant W : integer := A'range'high - A'range'low + 2;
    variable Temp : std_logic_vector(W-1 downto 0);
  begin
    Temp := std_logic_vector(-resize(signed(A), W));
    Temp := Saturate(Temp, W-1);
    return Temp(W-2 downto 0);
  end function;

  function Absolute(A : std_logic_vector) return std_logic_vector is
  begin
    if A(A'range'high) = '1' then
      return Negate(A);
    else
      return A;
    end if;
  end function;
end package body;
