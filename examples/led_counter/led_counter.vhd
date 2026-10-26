library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_counter is
    port (
        clk : in std_logic;
        led : out std_logic
    );
end entity;

architecture rtl of led_counter is
    signal counter : unsigned(23 downto 0) := (others => '0');
begin
    process (clk)
    begin
        if rising_edge(clk) then
            counter <= counter + 1;
        end if;
    end process;

    led <= counter(23);
end architecture;
