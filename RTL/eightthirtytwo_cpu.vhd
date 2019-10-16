library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eightthirtytwo_pkg.all;

-- To do:
-- Done - more testing needed: Flags - conditional execution
-- Sgn modifier
-- Hazards / stalls / bubbles
-- Load/store results
-- Predec / postinc

entity eightthirtytwo_cpu is
generic(
	pc_mask : std_logic_vector(31 downto 0) := X"ffffffff";
	stack_mask : std_logic_vector(31 downto 0) := X"ffffffff"
	);
port(
	clk : in std_logic;
	reset_n : in std_logic;
	addr : out std_logic_vector(31 downto 2);
	d : in std_logic_vector(31 downto 0);
	q : out std_logic_vector(31 downto 0);
	wr : out std_logic;
	req : out std_logic;
	ack : in std_logic;
	bytesel : out std_logic_vector(3 downto 0)
);
end entity;

architecture behavoural of eightthirtytwo_cpu is


-- Register file signals:

signal r_gpr_ra : std_logic_vector(2 downto 0);
signal r_gpr_q : std_logic_vector(31 downto 0);
signal r_gpr0 : std_logic_vector(31 downto 0);
signal r_gpr1 : std_logic_vector(31 downto 0);
signal r_gpr2 : std_logic_vector(31 downto 0);
signal r_gpr3 : std_logic_vector(31 downto 0);
signal r_gpr4 : std_logic_vector(31 downto 0);
signal r_gpr5 : std_logic_vector(31 downto 0);
signal r_gpr6 : std_logic_vector(31 downto 0);

signal r_tmp : std_logic_vector(31 downto 0); -- Working around a GHDL problem...

signal flag_z : std_logic;
signal flag_c : std_logic;

-- Load / store signals

signal ls_addr : std_logic_vector(31 downto 0);
signal ls_d : std_logic_vector(31 downto 0);
signal ls_q : std_logic_vector(31 downto 0);
signal ls_byte : std_logic;
signal ls_halfword : std_logic;
signal ls_req : std_logic;
signal ls_req_r : std_logic;
signal ls_wr : std_logic;
signal ls_ack : std_logic;


-- Fetch stage signals:

signal f_pc : std_logic_vector(31 downto 0);
signal f_op : std_logic_vector(7 downto 0);
signal f_prevop : std_logic_vector(7 downto 0);
signal f_op_valid : std_logic := '0' ;	-- Execute stage can use f_op


-- Decode stage signals:

signal d_alu_func : std_logic_vector(e32_alu_maxbit downto 0);
signal d_alu_reg1 : std_logic_vector(e32_reg_maxbit downto 0);
signal d_alu_reg2 : std_logic_vector(e32_reg_maxbit downto 0);
signal d_ex_op : std_logic_vector(e32_ex_maxbit downto 0);
signal d_run : std_logic;

-- Execute stage signals:

signal e_alu_func : std_logic_vector(e32_alu_maxbit downto 0);
signal e_alu_reg1 : std_logic_vector(e32_reg_maxbit downto 0);
signal e_alu_reg2 : std_logic_vector(e32_reg_maxbit downto 0);
signal e_reg : std_logic_vector(2 downto 0);
signal e_ex_op : std_logic_vector(e32_ex_maxbit downto 0);
signal e_cond : std_logic;
signal cond_minterms : std_logic_vector(3 downto 0);

signal e_setpc : std_logic;

signal alu_imm : std_logic_vector(5 downto 0);
signal alu_d1 : std_logic_vector(31 downto 0);
signal alu_d2 : std_logic_vector(31 downto 0);
signal alu_op : std_logic_vector(e32_alu_maxbit downto 0);
signal alu_q1 : std_logic_vector(31 downto 0);
signal alu_q2 : std_logic_vector(31 downto 0);
signal alu_sgn : std_logic;
signal alu_req : std_logic;
signal alu_carry : std_logic;
signal alu_ack : std_logic;
signal alu_busy :std_logic;


-- Memory stage signals

signal m_alu_reg1 : std_logic_vector(e32_reg_maxbit downto 0);
signal m_alu_reg2 : std_logic_vector(e32_reg_maxbit downto 0);
signal m_reg : std_logic_vector(2 downto 0);
signal m_ex_op : std_logic_vector(e32_ex_maxbit downto 0);

-- Writeback stage signals

signal w_alu_reg1 : std_logic_vector(e32_reg_maxbit downto 0);
signal w_alu_reg2 : std_logic_vector(e32_reg_maxbit downto 0);
signal w_reg : std_logic_vector(2 downto 0);
signal w_ex_op : std_logic_vector(e32_ex_maxbit downto 0);

-- hazard / stall signals
signal hazard_tmp : std_logic;
signal hazard_pc : std_logic;
signal hazard_reg : std_logic;
signal hazard_load : std_logic;
signal hazard_flags : std_logic;
signal e_blocked : std_logic;

begin

-- Decoder

decoder: entity work.eightthirtytwo_decode
port map(
	clk => clk,
	reset_n => reset_n,
	opcode => f_op,
	alu_func => d_alu_func,
	alu_reg1 => d_alu_reg1,
	alu_reg2 => d_alu_reg2,
	ex_op => d_ex_op
);


-- Fetch/Load/Store unit is responsible for interfacing with main memory.
fetchloadstore : entity work.eightthirtytwo_fetchloadstore 
generic map(
	pc_mask => X"ffffffff"
	)
port map
(
	clk => clk,
	reset_n => reset_n,

	-- cpu fetch interface

	pc => f_pc,
	pc_req => e_setpc,
	opcode => f_op,
	opcode_valid => f_op_valid,

	-- cpu load/store interface

	ls_addr => ls_addr,
	ls_d => ls_d,
	ls_q => ls_q,
	ls_wr => ls_wr,
	ls_byte => ls_byte,
	ls_halfword => ls_halfword,
	ls_req => ls_req,
	ls_ack => ls_ack,

		-- external RAM interface:

	ram_addr => addr,
	ram_d => d,
	ram_q => q,
	ram_bytesel => bytesel,
	ram_wr => wr,
	ram_req => req,
	ram_ack => ack
);


-- Register file logic:

r_gpr_ra<=f_op(2 downto 0);
with r_gpr_ra select r_gpr_q <=
	r_gpr0 when "000",
	r_gpr1 when "001",
	r_gpr2 when "010",
	r_gpr3 when "011",
	r_gpr4 when "100",
	r_gpr5 when "101",
	r_gpr6 when "110",
	f_pc when "111",
	(others=>'X') when others;	-- r7 is the program counter. FIXME - Needs to return f_pc+1



-- Execute

alu : entity work.eightthirtytwo_alu
port map(
	clk => clk,
	reset_n => reset_n,

	imm => alu_imm,
	d1 => alu_d1,
	d2 => alu_d2,
	op => alu_op,
	sgn => alu_sgn,
	req => alu_req,

	q1 => alu_q1,
	q2 => alu_q2,
	carry => alu_carry,
	ack => alu_ack
);


-- Load/store

ls_req<=ls_req_r and not ls_ack;





-- Store stage



-- Hazard / stall logic.
-- We don't yet attempt any results forwarding or instruction fusing.

-- f_op_valid:
-- If the opcode supplied for the current PC is invalid, we must block D and the transfer
-- to E - but E, M and W must operate as usual, filling up with bubbles.

-- hazard_tmp:
-- If the instruction being decoded requires tmp as either source we
-- block the transfer from D to E and the advance of PC
-- until any previous instruction writing to tmp has cleared the pipeline.
-- (If we don't implement ltmpinc or ltmp then nothing beyond M will write to tmp.)


hazard_tmp<='1' when
	(e_ex_op(e32_exb_q1totmp)='1' or e_ex_op(e32_exb_q2totmp)='1'
		or m_ex_op(e32_exb_q1totmp)='1' or m_ex_op(e32_exb_q2totmp)='1'
		or w_ex_op(e32_exb_q1totmp)='1' or w_ex_op(e32_exb_q2totmp)='1')
		and (d_alu_reg1(e32_regb_tmp)='1' or d_alu_reg2(e32_regb_tmp)='1')
	else '0';

-- hazard_reg:
-- If the instruction being decoded requires a register as source we block
-- the transfer from D to E and the advance of PC until any previous
-- instruction writing to the regfile has cleared the pipeline.
-- (FIXME Can potentially make this finer-grained and match the actual register, but
-- then need to consider clashes between M and W for writing to the regfile.
-- Second write port?  If we don't implement ltmpinc then all loads write to tmp anyway.)
hazard_reg<='1' when
	(e_ex_op(e32_exb_q1toreg)='1'
		or m_ex_op(e32_exb_q1toreg)='1'
--		or w_ex_op(e32_exb_q1toreg)='1'
			)
		and ((d_alu_reg1(e32_regb_gpr)='1' or d_alu_reg2(e32_regb_gpr)='1'))
	else '0';

-- FIXME - need an e32_exb_q1topc bit
hazard_pc<='1' when
	(e_ex_op(e32_exb_q1toreg)='1' and e_reg="111")
		or (m_ex_op(e32_exb_q1toreg)='1' and m_reg="111")
		or (w_ex_op(e32_exb_q1toreg)='1' and w_reg="111")
	else '0';

-- FIXME - this won't work if we implement ltmpinc since we'll then be writing to regfile in W.
hazard_load<='1' when
	(e_ex_op(e32_exb_load)='1' or m_ex_op(e32_exb_load)='1' or w_ex_op(e32_exb_load)='1')
		and (d_alu_reg1(e32_regb_tmp)='1' or d_alu_reg2(e32_regb_tmp)='1')
	else '0';

hazard_flags<='1' when
	e_ex_op(e32_exb_cond)='1' and (m_ex_op(e32_exb_flags)='1' or w_ex_op(e32_exb_load)='1')
	else '0';

-- ALU busy logic:
-- Some ALU operations are two-cycle, notably mul and post-increment operations.
-- (The latter so that the M logic can use the old value to trigger a memory
-- operation before writing the new value to the regfile.)
-- Shift operations can take many cycles.
-- While the ALU is busy the PC can't increment, however we do want mem ops to be
-- triggered (once), then the op to handed over to M when the op finishes.

e_blocked<=hazard_tmp or hazard_reg or hazard_pc or hazard_load or (alu_busy and not alu_ack);

--	alu_op<=e_alu_func;
--	alu_imm<=f_op(5 downto 0);
--	alu_d1<=r_tmp when e_alu_reg1(e32_regb_tmp)='1' else
--		f_pc when e_alu_reg1(e32_regb_pc)='1' else
--		r_gpr_q;
--		
--	alu_d2<=r_tmp when e_alu_reg2(e32_regb_tmp)='1' else
--		f_pc when e_alu_reg2(e32_regb_pc)='1' else
--		r_gpr_q;
--	alu_req<='1';

-- Condition minterms:

cond_minterms(3)<= flag_z and flag_c;
cond_minterms(2)<= (not flag_z) and flag_c;
cond_minterms(1)<= flag_z and (not flag_c);
cond_minterms(0)<= (not flag_z) and (not flag_c);

process(clk,reset_n,f_op_valid)
begin
	if reset_n='0' then
		f_pc<=(others=>'0');
		e_setpc<='1';
		ls_req_r<='0';
		ls_wr<='0';
		e_cond<='0';
		alu_sgn<='0';
		alu_busy<='0';
		e_ex_op<=e32_ex_bubble;
	elsif rising_edge(clk) then
		d_run<='1';
		e_setpc<='0';
		alu_req<='0';

		if d_run='1' and f_op_valid='1' then

			-- Decode stage:

			-- Set ALU registers
			alu_imm<=f_op(5 downto 0);
			
			alu_op<=d_alu_func;
			if d_alu_reg1(e32_regb_tmp)='1' then
				alu_d1<=r_tmp;
			elsif d_alu_reg1(e32_regb_pc)='1' then
				alu_d1<=std_logic_vector(unsigned(f_pc)+1);
			else
				alu_d1<=r_gpr_q;
			end if;

			if d_alu_reg2(e32_regb_tmp)='1' then
				alu_d2<=r_tmp;
			elsif d_alu_reg2(e32_regb_pc)='1' then
				alu_d2<=std_logic_vector(unsigned(f_pc)+1);
			else
				alu_d2<=r_gpr_q;
			end if;

			if d_ex_op(e32_exb_waitalu)='1' and alu_busy='0' and e_blocked='0' then
				alu_req<='1';
				alu_busy<='1';
			end if;
			if alu_ack='1' then
				alu_busy<='0';
			end if;
			
			-- Execute stage:  (Can we do some this combinationally? Probably not -
			-- must be registered so it doesn't change during ALU op.

			-- If we have a hazard or we're blocked by conditional execution
			-- then we insert a bubble,
			-- otherwise advance the PC, forward context from D to E.

			if e_blocked='1' or (d_ex_op(e32_exb_waitalu)='1' and alu_ack='0') then
				e_ex_op<=e32_ex_bubble;
			else
				f_pc<=std_logic_vector(unsigned(f_pc)+1);
				e_alu_func<=d_alu_func;
				e_alu_reg1<=d_alu_reg1;
				e_alu_reg2<=d_alu_reg2;
				e_reg<=f_op(2 downto 0);
				e_ex_op<=d_ex_op;
			end if;
			

			-- Mem stage

			-- Forward context from E to M
			m_alu_reg1<=e_alu_reg1;
			m_alu_reg2<=e_alu_reg2;
			m_reg<=e_reg;
			m_ex_op<=e_ex_op;

			-- FIXME - how to handle predec / postinc addresses?

			-- Record flags from ALU
			if m_ex_op(e32_exb_flags)='1' then
				flag_c<=alu_carry;
				if alu_q1=X"00000000" then
					flag_z<='1';
				else
					flag_z<='0';
				end if;
			end if;
			
			ls_halfword<=m_ex_op(e32_exb_halfword);
			ls_byte<=m_ex_op(e32_exb_halfword);
			if m_ex_op(e32_exb_load)='1' then
				ls_addr<=alu_q1;
				ls_req_r<='1';
			end if;			

			if m_ex_op(e32_exb_store)='1' then
				ls_addr<=alu_q1;
				ls_d<=alu_q2;
				ls_wr<='1';
				ls_req_r<='1';
			end if;			
		
			-- FIXME - Need to make sure ALU results are correctly stored
			-- for all ldinc / stdec variants
			if m_ex_op(e32_exb_q1totmp)='1' then
				r_tmp<=alu_q1;
			elsif m_ex_op(e32_exb_q2totmp)='1' then
				r_tmp<=alu_q2;
			end if;

			if m_ex_op(e32_exb_q1toreg)='1' then
				case m_reg(2 downto 0) is
					when "000" =>
						r_gpr0<=alu_q1;
					when "001" =>
						r_gpr1<=alu_q1;
					when "010" =>
						r_gpr2<=alu_q1;
					when "011" =>
						r_gpr3<=alu_q1;
					when "100" =>
						r_gpr4<=alu_q1;
					when "101" =>
						r_gpr5<=alu_q1;
					when "110" =>
						r_gpr6<=alu_q1;
					when "111" =>
						e_setpc<='1';
						f_pc<=alu_q1;
					when others =>
						null;
				end case;
			end if;

			-- Writeback stage

			if ls_req_r='0' or ls_ack='1' then
				if m_ex_op(e32_exb_load)='1' or m_ex_op(e32_exb_store)='1' then
					w_alu_reg1<=m_alu_reg1;
					w_alu_reg2<=m_alu_reg2;
					w_reg<=m_reg;
					w_ex_op<=m_ex_op;
				else
					w_ex_op<=e32_ex_bubble;
				end if;
			end if;

			if w_ex_op(e32_exb_store)='1' and ls_ack='1' then
				ls_req_r<='0';
			end if;			

			-- FIXME - stall pipeline based on write to PC or write to reg
			-- FIXME - if we're going to support ldtmpinc we need to have
			-- a way of signalling load target.  All other loads go to tmp.
			if w_ex_op(e32_exb_load)='1' and ls_ack='1' then
				ls_req_r<='0';
--				if w_alu_reg2(e32_regb_tmp)='1' then
					r_tmp<=ls_q;
--				elsif w_alu_reg2(e32_regb_pc)='1' then
--					f_pc<=ls_q;
--					e_setpc<='1';
--				else
--					r_gpr_wa<=w_reg;
--					r_gpr_wr<='1';
--				end if;		
			end if;

			
			-- Conditional execution:

			if e_cond='1' then	-- advance PC but replace instructions with bubbles
				e_ex_op<=e32_ex_bubble;
				m_ex_op<=e32_ex_bubble;
				if d_ex_op(e32_exb_q1toreg)='1' and f_op(2 downto 0)="111" then -- Writing to PC?
					e_ex_op<=e32_ex_cond;
				end if;
			end if;


			if e_ex_op(e32_exb_cond)='1' then
				if (e_reg(1)&e_reg and cond_minterms) = "0000" then
					e_cond<='1';
				else
					e_cond<='0';
				end if;			
			end if;

			
		end if;
		
	end if;

	
end process;


end architecture;

