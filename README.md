# EightThirtyTwo
An experimental CPU core with 8-bit instruction words and 32-bit registers.
Copyright (c) 2019, 2020 by Alastair M. Robinson

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

	The authors and maintainers of vbcc have permission to include the vbcc C
	compiler backend in source and binary distributions of the vbcc C compiler
	without being bound by the terms of the GNU GPL.

## Scope
The project includes a synthesizable CPU core, an assembler, linker,
disassembler and emulator and a backend for the vbcc C compiler.

## Goals
The main design goals are modest logic footprint and minimum possible use
of BlockRAM - which is achieved by (a) aiming to maximise code density,
and (b) having the register file implemented as logic rather than BlockRAM.

In order to maximise code density, the instruction words are only 1-byte
long, with only three bits devoted to the operand.  This allows one of
eight general purpose registers to be selected, while a ninth "tmp" register
provides an implicit second operand.

There is optional support for dual threads, and the CPU offers full
load/store alignment, build-time switchable endian-ness and 32 x 32 to
64 bit multiplication.

## Registers
* r0 - r6 - General Purpose Registers.  R6 is suggested as a stack pointer
but nothing in the ISA enforces this.
* r7 - Program Counter.  Only bits 0 - 29 of this are used as an address;
bits 30-31 are used internally as flags to simplify context switching.
* tmp - Implicit second operand

## Program counter and flow control
There are no branch, jump or return instructions; instead these operations
are performed by manipulating r7, which is designated as the Program Counter.
Reads from r7 return the current PC + 1, i.e. the address of the next
instruction to be executed; the instruction "exg r7" will jump to a 
subroutine address in tmp, at the same time moving the return address into
tmp.  The add instruction is special-cased for r7 - it normally leaves tmp
untouched, but for r7 it places its previous value in tmp - again providing
a return address, this time for a PC-relative branch.

## Flags
* Zero - set if the result of the last ALU operation or memory load was zero.
* Carry - set if the last ALU operation overflowed.  In order to accommodate
both signed and unsigned comparisons the meaning of the carry bit can be
modified with a "sgn" instruction.
* Cond - set if a "cond" instruction's predicates weren't met, and thus 
instructions should be skipped over.  Cleared by either a subsequent "cond"
instruction or by passing an instruction that would have changed program flow
by writing to r7.
* Sign - set by the "sgn" instruction, and cleared by the next ALU instruction.

## Conditional execution
There are no conditional branch instructions; instead we have a "cond"
instruction which predicates the following instructions upon a condition
being met.  Valid conditions are:
* EX - execute no matter what.
* NEX - don't execute no matter what. (Pauses the CPU until the next interrupt.)
* EQ - execute only if the last result was equal to zero.
* NEQ - execute only if the last result was not zero.
* SLT - execute only if the last result was strictly less than zero.
* LE - execute only if the last result was less than or equal to zero.
* SGT - execute only if the last result was strictly greater than zero.
* GE - execute only if the last result was greater than or equal to zero.

## Interrupts
A single interrupt signal is supported.  If the CPU is built with interrupt
support then on receipt of an interrupt the CPU will jump to location 0
with the Zero flag set.  Even if interrupts are disabled, a high pulse on
the interrupt signal will unpause the CPU if it's been paused with "cond NEX".

## Dual threads
The EightThirtyTwo CPU optionally supports dual execution threads, each with
its own register file and its own fetch, decode and hazard logic.
Both threads begin execution at location 0, the first with the carry flag
clear and the second with the carry flag set. Startup code will use these
flags to diverge the two execution threads, as well as interrupts.

## Instruction set
The ISA has 28 instructions, most of which take one nominated operand and
one implicit operand:

### Move instructions
* mr r&lt;n&gt;  -  Move the contents of the temp register to r&lt;n&gt;
* mt r&lt;n&gt;  -  Move the contents of r&lt;n&gt; to the temp register
* exg r&lt;n&gt;  -  Swap the contents of r&lt;n&gt; and the temp register

### Misc instructions
* li imm  -  Load a 6-bit immediate value to the temp register,
sign-extended to 32 bits.  If the previous instruction was also "li" then
tmp is shifted six bits left and the new immediate value is or-ed into the
lower six bits.  32 bits immediates can thus be loaded by chaining up to six
li instructions.  "ldinc r7" may be a better solution for larger immediates,
however.
* cond predicate  -  test the Z and C flags against predicate.  If the
test fails, subsequent instructions will be skipped until the CPU encounters
either another "cond" instruction or an instruction that would
have written to r7.
* sgn  -  Sets the sgn flag, which modifies the "cmp", "shr" and "mul"
instructions.  Any subsequent ALU instruction will clear it again.
* hlf  -  modifies the next load/store instruction to operate on halfwords
rather than full words.  Only modifies the storage size, doesn't modify
increment or decrement amounts.
* byt  -  modifies the next load/store instruction to operate on bytes
rather than full words.  Only modifies the storage size, doesn't modify
increment or decrement amounts.

### Load instructions
All load instructions will set or clear the zero flag based on the loaded
value.
* ld r&lt;n&gt;  -  Loads from the address in r&lt;n&gt; and writes the result to tmp.
* ldt  -  Loads from the address in tmp, and writes the result to tmp.
* ldinc r&lt;n&gt;  -  Loads from the address in r&lt;n&gt;, writes the result tmp,
increments r&lt;n&gt; by 4.
* ldbinc r&lt;n&gt;  -  Loads a single byte from the address in r&lt;n&gt;,
writes the result to tmp, increments r&lt;n&gt; by 1.
* ldidx r&lt;n&gt;  -   Loads from the sum of r&lt;n&gt; and tmp, writes the result to
tmp.

### Store instructions
* st r&lt;n&gt;  -  Stores the contents of tmp to the address in r&lt;n&gt;.
* stinc r&lt;n&gt;  -  Stores the contents of tmp to the address in r&lt;n&gt;, increments r&lt;n&gt;.
* stdec r&lt;n&gt;  -  Decrements r&lt;n&gt;, stores the contents of tmp to the address in r&lt;n&gt;.
* stbinc r&lt;n&gt;  -  Stores the lowest byte of tmp to the address in r&lt;n&gt;, increments r&lt;n&gt;
* stmpdec r&lt;n&gt;  -  Decrements tmp, stores the contents of r&lt;n&gt; to the address in tmp.

### Arithmetic, Bitwise and Shift instructions
All ALU instructions set or clear the Zero flag based on the result.
Add, addt, sub, cmp and mul will also set or clear the Carry flag.

* add r&lt;n&gt;  -  Add tmp to r&lt;n&gt;, write the result to r&lt;n&gt;.  If r&lt;n&gt; is r7 then
the old value will be written to tmp, allowing it to serve as a link register.
* addt r&lt;n&gt;  -  Add tmp to r&lt;n&gt;, write result to tmp.
* sub r&lt;n&gt;  -  Subtract tmp from r&lt;n&gt;
* cmp r&lt;n&gt;  -  Subtract tmp from r&lt;n&gt;, discard result but set flags.
* mul r&lt;n&gt;  -  32x32 to 64 bit multiply.  The upper 32 bits go to tmp, the
lower 32 bits go to r&lt;n&gt;.  The multiplication will be signed if the sgn flag
is set, unsigned otherwise.
* and r&lt;n&gt;  -  Bitwise and r&lt;n&gt; with tmp, result to r&lt;n&gt;
* or r&lt;n&gt;  -  Bitwise or r&lt;n&gt; with tmp, result to r&lt;n&gt;
* xor r&lt;n&gt;  -  Bitwise xor r&lt;n&gt; with tmp, result to r&lt;n&gt;
* shl r&lt;n&gt;  -  Shift r&lt;n&gt; left by tmp bits.
* shr r&lt;n&gt;  -  Shift r&lt;n&gt; right by tmp bits.  If the sgn flag is clear then
zeroes will be shifted in - otherwise the leftmost bit of r&lt;n&gt; will be copied.
* ror r&lt;n&gt;  -  Rotate r&lt;n&gt; right by tmp bits.

Note: The shift and rotate instructions are slow - if you're shifting by a
fixed amount the mul instruction will be faster.

## Assembler
The assembler is called "832a", and should be invoked like so:

832a (options) file.asm (file2.asm ...)

Valid options are:
* -o outputfile  -  specify the output file name.  Only valid if assembling a single file.
If no output file is specified, "file.asm" will be assembled to "file.o".
* -d - enable debug output.

As well as the 832 opcodes listed above, the assembler recognises the following directives:
* .liconst value - emit one or more 'li' instructions, however many are required to load value into tmp.
* .liabs value - emit one or more 'li' instructions, loading the address of symbol into tmp.
* .lipcrel symbol - emit one or more 'li' instructions, loading the PC-relative address of symbol into tmp.
* .incbin - include a binary file.
* .ctor sectionname - define a constructor section.  The sections are sorted in ascii order at link time.
* .dtor sectionname - define a destructor section.  The sections are reverse-sorted in ascii order at link time.
* .bss sectionname - define a BSS section
* .global symbolname - declare a symbol as having global scope
* .weak symbolname - declare a symbol as having weak linkage.  At link time all objects will be scanned for symbols sharing this name.  If one is found without weak linkage it will be used.  If all instances have weak linkage, the last one found will be used.
* .section sectionname - declare a new section
* .constant name,value - declare a constant to be referenced by .liconst.
* .align value - align the next item to the a boundary of value bytes.
* .comm var - declare an uninitialised variable with global scope.
* .lcomm var - declare an uninitialised variable with local scope.
* .ref symbol - include the address of symbol as a 32-bit value.
* .int value - embed a 32-bit integer value
* .short value - embed a 16-bit integer value
* .byte value - embed an 8-bit integer value
* .space size,value - declare an area of size bytes, filled with value.

## Linker
The linker is called "832l", and should be invoked like so:

832l (options) file.o (file2.o ...)

Valid options are
* -o outputfile - specify the output file name.  If none is specified, the linked program will be written to "a.out".
* -b number - specify base address
* -s symbol=number - define symbol (such as stack size)
* -d - enable debug messages

