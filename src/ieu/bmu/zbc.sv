///////////////////////////////////////////
// zbc.sv
//
// Written: Kevin Kim <kekim@hmc.edu> and Kip Macsai-Goren <kmacsaigoren@hmc.edu>
// Created: 2 February 2023
// Modified: 3 March 2023
//
// Purpose: RISC-V ZBC top-level unit
//
// Documentation: RISC-V System on Chip Design Chapter 15
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

`include "wally-config.vh"

module zbc #(parameter WIDTH=32) (
  input  logic [WIDTH-1:0] A, RevA, B,       // Operands
  input  logic [2:0]       Funct3,           // Indicates operation to perform
  output logic [WIDTH-1:0] ZBCResult);       // ZBC result

  logic [WIDTH-1:0] ClmulResult, RevClmulResult;
  logic [WIDTH-1:0] RevB;
  logic [WIDTH-1:0] x,y;
  logic [1:0] select;

  assign select = ~Funct3[1:0];

  bitreverse #(WIDTH) brB(.A(B), .RevA(RevB));

  mux3 #(WIDTH) xmux({RevA[WIDTH-2:0], {1'b0}}, RevA, A, select, x);
  mux3 #(WIDTH) ymux({{1'b0},RevB[WIDTH-2:0]}, RevB, B,  select, y);

  clmul #(WIDTH) clm(.A(x), .B(y), .ClmulResult(ClmulResult));
  
  bitreverse  #(WIDTH) brClmulResult(.A(ClmulResult), .RevA(RevClmulResult));

  mux2 #(WIDTH) zbcresultmux(ClmulResult, RevClmulResult, Funct3[1], ZBCResult);
endmodule