///////////////////////////////////////////
// WALLY-init-lib.h
//
// Written: David_Harris@hmc.edu 21 March 2023
//
// Purpose: Initialize stack, handle interrupts, terminate test case
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// 
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file 
// except in compliance with the License, or, at your option, the Apache License version 2.0. You 
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the 
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
// either express or implied. See the License for the specific language governing permissions 
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

// load code to initalize stack, handle interrupts, terminate

.section .text.init
.global rvtest_entry_point

rvtest_entry_point:
    la sp, topofstack       # Initialize stack pointer (not used)

    # Set up interrupts
    la t0, trap_handler
    csrw mtvec, t0      # Initialize MTVEC to trap_handler
    csrw mideleg, zero  # Don't delegate interrupts
    csrw medeleg, zero  # Don't delegate exceptions
    csrw mie, t0        # Enable machine timer interrupt
    la t0, topoftrapstack 
    csrw mscratch, t0   # MSCRATCH holds trap stack pointer
    csrsi mstatus, 0x8  # Turn on mstatus.MIE global interrupt enable
    j main              # Call main function in user test program

done:
    li a0, 4            # argument to finish program    
    ecall               # system call to finish program
    j self_loop         # wait forever (not taken)

.align 4                # trap handlers must be aligned to multiple of 4
trap_handler:
    # Load trap handler stack pointer tp
    csrrw tp, mscratch, tp  # swap MSCRATCH and tp
    sd t0, 0(tp)        # Save t0 and t1 on the stack
    sd t1, -8(tp)
    csrr t0, mcause     # Check the cause
    csrr t1, mtval      # And the trap value
    bgez t0, exception  # if msb is clear, it is an exception

interrupt:              # must be a timer interrupt 
    j trap_return       # clean up and return

exception:
    csrr t1, mepc   # add 4 to MEPC to determine return Address
    addi t1, t1, 4
    csrw mepc, t1
    li t1, 8            # is it an ecall trap?
    andi t0, t0, 0xFC # if CAUSE = 8, 9, or 11
    bne t0, t1, trap_return # ignore other exceptions

ecall:
    li t0, 4
    beq a0, t0, write_tohost    # call 4: terminate program
    bltu a0, t0, changeprivilege    # calls 0-3: change privilege level
    j trap_return       # ignore other ecalls

changeprivilege:
    li t0, 0x00001800   # mask off mstatus.MPP in bits 11-12
    csrc mstatus, t0
    andi a0, a0, 0x003  # only keep bottom two bits of argument
    slli a0, a0, 11     # move into mstatus.MPP position
    csrs mstatus, a0    # set mstatus.MPP with desired privilege

trap_return:            # return from trap handler
    ld t1, -8(tp)       # restore t1 and t0
    ld t0, 0(tp)
    csrrw tp, mscratch, tp  # restore tp
    mret                # return from trap

write_tohost:
    la t1, tohost
    li t0, 1            # 1 for success, 3 for failure
    sd t0, 0(t1)        # send success code

self_loop:
    j self_loop         # wait
    
.section .tohost 
tohost:                 # write to HTIF
    .dword 0
fromhost:
    .dword 0

.EQU XLEN,64
begin_signature:
    .fill 6*(XLEN/32),4,0xdeadbeef    # 
end_signature:

# Initialize stack with room for 512 bytes
.bss
    .space 512
topofstack:
# And another stack for the trap handler
.bss   
    .space 512
topoftrapstack:

.align 4
.section .text.main
