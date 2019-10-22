library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eightthirtytwo_pkg.all;

entity eightthirtytwo_decode is
port(
	clk : in std_logic;
	reset_n : in std_logic;
	opcode : in std_logic_vector(7 downto 0);
	alu_func : out std_logic_vector(e32_alu_maxbit downto 0);
	alu_reg1 : out std_logic_vector(e32_reg_maxbit downto 0);
	alu_reg2 : out std_logic_vector(e32_reg_maxbit downto 0);
	ex_op : out std_logic_vector(e32_ex_maxbit downto 0)
);
end entity;


architecture behavoural of eightthirtytwo_decode is

signal op : std_logic_vector(7 downto 0);
signal reg : std_logic_vector(e32_reg_maxbit downto 0);
signal addop : std_logic_vector(e32_ex_maxbit downto 0);
signal orop : std_logic_vector(e32_ex_maxbit downto 0);
signal xorop : std_logic_vector(e32_ex_maxbit downto 0);
signal xoraluop : std_logic_vector(e32_alu_maxbit downto 0);

begin

-- Decode stage, combinational logic:

-- Special case for li and overloaded instructions:

-- li only uses 2 bits for decoding; the other two bits are are of the immediate value

op<="11000000" when opcode(7 downto 6)="11" else opcode(7 downto 3)&"000";

-- Add is overloaded when r=7; old value goes to temp.
addop<=e32_ex_q1toreg or e32_ex_q2totmp when opcode(2 downto 0)="111"
	else e32_ex_q1toreg or e32_ex_flags;

-- Or is overloaded when r=7; becomes the sgn instruction
orop<=e32_ex_sgn when opcode(2 downto 0)="111"
	else e32_ex_q1toreg or e32_ex_flags;

-- Xor is overloaded when r=7; becomes the ldt instruction
xorop<=e32_ex_load when opcode(2 downto 0)="111"
	else e32_ex_q1toreg or e32_ex_flags;

xoraluop<=e32_alu_nop when opcode(2 downto 0)="111"
	else e32_alu_xor;


-- ALU functions

with op select alu_func <=
	e32_alu_nop when e32_op_cond,
	e32_alu_nop when e32_op_mr,
	e32_alu_nop when e32_op_sth,
	e32_alu_nop when e32_op_st,

	e32_alu_nop when e32_op_ld,
	e32_alu_sub when e32_op_sub,
	e32_alu_sub when e32_op_cmp,
	e32_alu_incb when e32_op_stbinc,

	e32_alu_incw when e32_op_ldinc,
	e32_alu_add when e32_op_ldidx,
	e32_alu_incb when e32_op_ldbinc,
	e32_alu_decw when e32_op_stdec,

	e32_alu_decw when e32_op_stmpdec,
	e32_alu_li when e32_op_li,
	e32_alu_and when e32_op_and,
	e32_alu_or when e32_op_or,

	xoraluop when e32_op_xor,
	e32_alu_shl when e32_op_shl,
	e32_alu_shr when e32_op_shr,
	e32_alu_ror when e32_op_ror,

	e32_alu_mul when e32_op_mul,
	e32_alu_exg when e32_op_exg,
	e32_alu_nop when e32_op_mt,
	e32_alu_add when e32_op_add,

	e32_alu_addt when e32_op_addt,
	e32_alu_nop when others;


-- Register to ALU mappings:

with op select alu_reg1 <=
	e32_reg_tmp when e32_op_mr,
	e32_reg_tmp when e32_op_ldidx,
	e32_reg_tmp when e32_op_stmpdec,
	e32_reg_tmp when e32_op_exg,
	e32_reg_tmp when e32_op_add, -- Swapped because we want the old value in q2
	e32_reg_gpr when e32_op_sth,
	e32_reg_gpr when e32_op_st,

	e32_reg_gpr when e32_op_ld,
	e32_reg_gpr when e32_op_sub,
	e32_reg_gpr when e32_op_cmp,
	e32_reg_gpr when e32_op_stbinc,

	e32_reg_gpr when e32_op_ldinc,
	e32_reg_gpr when e32_op_ldbinc,
	e32_reg_gpr when e32_op_stdec,

	e32_reg_gpr when e32_op_and,
	e32_reg_gpr when e32_op_or,

	e32_reg_tmp when e32_op_xor,	-- Swapped because we overload xor r7 as ldt
	e32_reg_gpr when e32_op_shl,
	e32_reg_gpr when e32_op_shr,
	e32_reg_gpr when e32_op_ror,

	e32_reg_gpr when e32_op_mul,
	e32_reg_gpr when e32_op_mt,

	e32_reg_gpr when e32_op_addt,
	e32_reg_dontcare when e32_op_cond,
	e32_reg_dontcare when others;


with op select alu_reg2 <=
	e32_reg_gpr when e32_op_stmpdec,
	e32_reg_gpr when e32_op_exg,
	e32_reg_gpr when e32_op_add, -- Swapped because we want the old value in q2
	e32_reg_tmp when e32_op_mr,
	e32_reg_tmp when e32_op_sth,
	e32_reg_tmp when e32_op_st,

	e32_reg_dontcare when e32_op_ld,
	e32_reg_tmp when e32_op_sub,
	e32_reg_tmp when e32_op_cmp,
	e32_reg_tmp when e32_op_stbinc,

	e32_reg_dontcare when e32_op_ldinc,
	e32_reg_gpr when e32_op_ldidx,
	e32_reg_dontcare when e32_op_ldbinc,
	e32_reg_tmp when e32_op_stdec,

	e32_reg_tmp when e32_op_and,
	e32_reg_tmp when e32_op_or,

	e32_reg_gpr when e32_op_xor,	-- Swapped because we overload xor r7 as ldt.
	e32_reg_tmp when e32_op_shl,
	e32_reg_tmp when e32_op_shr,
	e32_reg_tmp when e32_op_ror,

	e32_reg_tmp when e32_op_mul,
	e32_reg_tmp when e32_op_mt,

	e32_reg_tmp when e32_op_addt,
	e32_reg_dontcare when e32_op_li,
	e32_reg_dontcare when e32_op_cond,
	e32_reg_dontcare when others;

	
-- FIXME - if we implement ldtmpinc, its result has to go to the regfile. How to deal with this?

-- Some ALU operations take more than one cycle; indicate this with exb_waitalu

with op select ex_op <=
	e32_ex_cond when e32_op_cond,
	e32_ex_q1totmp when e32_op_mt,
	e32_ex_q1toreg when e32_op_mr,

	e32_ex_flags when e32_op_cmp,

	(e32_ex_store or e32_ex_halfword) when e32_op_sth,
	e32_ex_store when e32_op_st,

	e32_ex_load when e32_op_ld,
	(e32_ex_q1toreg or e32_ex_flags) when e32_op_sub,
	(e32_ex_postinc or e32_ex_store or e32_ex_q1toreg or e32_ex_byte) when e32_op_stbinc,
	(e32_ex_store or e32_ex_q1toreg) when e32_op_stdec,

	(e32_ex_postinc or e32_ex_load or e32_ex_q1toreg) when e32_op_ldinc,
	e32_ex_load when e32_op_ldidx,
	(e32_ex_postinc or e32_ex_load or e32_ex_q1toreg or e32_ex_byte) when e32_op_ldbinc,

	(e32_ex_store or e32_ex_q1totmp) when e32_op_stmpdec,
	e32_ex_q2totmp when e32_op_li,
	(e32_ex_q1toreg or e32_ex_flags) when e32_op_and,
--	(e32_ex_q1toreg or e32_ex_flags) when e32_op_or,
	orop when e32_op_or,

--	(e32_ex_q1toreg or e32_ex_flags) when e32_op_xor,
	xorop when e32_op_xor,
	(e32_ex_q1toreg or e32_ex_flags or e32_ex_waitalu) when e32_op_shl,
	(e32_ex_q1toreg or e32_ex_flags or e32_ex_waitalu) when e32_op_shr,
	(e32_ex_q1toreg or e32_ex_flags or e32_ex_waitalu) when e32_op_ror,

	(e32_ex_q1toreg or e32_ex_q2totmp) when e32_op_exg,
	(e32_ex_q1toreg or e32_ex_q2totmp or e32_ex_flags or e32_ex_waitalu) when e32_op_mul,
	addop when e32_op_add, -- Overloaded so we can modify its behaviour with r7

	(e32_ex_q1totmp or e32_ex_flags) when e32_op_addt,
	(others => 'X') when others;

end architecture;
