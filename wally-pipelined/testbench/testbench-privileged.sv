///////////////////////////////////////////
// testbench-privileged.sv
//
// Written: Ben Bracker (bbracker@hmc.edu) 11 Feb. 2021, Tiny Modifications: Domenico Ottolia (dottolia@hmc.edu) 16 Mar. 2021 
// Based on: testbench-imperas.sv by David Harris
//
// Purpose: Wally Testbench and helper modules
//          Applies test programs meant to test peripherals
//          These tests assume the processor itself is already working!
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
// is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////

`include "wally-config.vh"

module testbench();
  logic        clk;
  logic        reset;

  int test, i, errors, totalerrors;
  logic [31:0] sig32[0:10000];
  logic [`XLEN-1:0] signature[0:10000];
  logic [`XLEN-1:0] testadr;
  string InstrFName, InstrDName, InstrEName, InstrMName, InstrWName;
  logic [31:0] InstrW;
  logic [`XLEN-1:0] meminit;

  string tests[] = '{                 
    "rv64p/WALLY-CAUSE", "0"
  };

  logic [`AHBW-1:0] HRDATAEXT;
  logic             HREADYEXT, HRESPEXT;
  logic [31:0]      HADDR;
  logic [`AHBW-1:0] HWDATA;
  logic             HWRITE;
  logic [2:0]       HSIZE;
  logic [2:0]       HBURST;
  logic [3:0]       HPROT;
  logic [1:0]       HTRANS;
  logic             HMASTLOCK;
  logic             HCLK, HRESETn;

  
  // pick tests based on modes supported
  // *** actually I no longer support this
  // would need to put this back in if you wanted to test anything other than rv64i

  string signame, memfilename;

  logic [31:0] GPIOPinsIn, GPIOPinsOut, GPIOPinsEn;
  logic UARTSin, UARTSout;

  // instantiate device to be tested
  assign GPIOPinsIn = 0;
  assign UARTSin = 1;
  assign HREADYEXT = 1;
  assign HRESPEXT = 0;
  assign HRDATAEXT = 0;

  wallypipelinedsoc dut(.*); 

  // Track names of instructions
  instrTrackerTB it(clk, reset, dut.hart.ieu.dp.FlushE,
                dut.hart.ifu.InstrD, dut.hart.ifu.InstrE,
                dut.hart.ifu.InstrM,  InstrW,
                InstrDName, InstrEName, InstrMName, InstrWName);

  // initialize tests
  initial
    begin
      test = 0;
      totalerrors = 0;
      testadr = 0;
      // fill memory with defined values to reduce Xs in simulation
      if (`XLEN == 32) meminit = 32'hFEDC0123;
      else meminit = 64'hFEDCBA9876543210;
      for (i=0; i<=65535; i = i+1) begin
        //dut.imem.RAM[i] = meminit;
       // dut.uncore.RAM[i] = meminit;
      end
      // read test vectors into memory
      memfilename = {"../../imperas-riscv-tests/work/", tests[test], ".elf.memfile"};
      $readmemh(memfilename, dut.imem.RAM);
      $readmemh(memfilename, dut.uncore.dtim.RAM);
      reset = 1; # 22; reset = 0;
    end

  // generate clock to sequence tests
  always
    begin
      clk = 1; # 5; clk = 0; # 5;
    end
   
  // check results
  always @(negedge clk)
    begin    
      if (dut.hart.priv.EcallFaultM && 
          (dut.hart.ieu.dp.regf.rf[3] == 1 || (dut.hart.ieu.dp.regf.we3 && dut.hart.ieu.dp.regf.a3 == 3 && dut.hart.ieu.dp.regf.wd3 == 1))) begin
        $display("Code ended with ecall with gp = 1");
        #60; // give time for instructions in pipeline to finish
        // clear signature to prevent contamination from previous tests
        for(i=0; i<10000; i=i+1) begin
          sig32[i] = 'bx;
        end

        // read signature, reformat in 64 bits if necessary
        signame = {"../../imperas-riscv-tests/work/", tests[test], ".signature.output"};
        $readmemh(signame, sig32);
        i = 0;
        while (i < 10000) begin
          if (`XLEN == 32) begin
            signature[i] = sig32[i];
            i = i+1;
          end else begin
            signature[i/2] = {sig32[i+1], sig32[i]};
            i = i + 2;
          end
        end

        // Check errors
        i = 0;
        errors = 0;
        if (`XLEN == 32)
          testadr = (`TIMBASE+tests[test+1].atohex())/4;
        else
          testadr = (`TIMBASE+tests[test+1].atohex())/8;
        /* verilator lint_off INFINITELOOP */
        while (signature[i] !== 'bx) begin
          //$display("signature[%h] = %h", i, signature[i]);
          if (signature[i] !== dut.uncore.dtim.RAM[testadr+i]) begin
            if (signature[i+4] !== 'bx || signature[i] !== 32'hFFFFFFFF) begin
              // report errors unless they are garbage at the end of the sim
              // kind of hacky test for garbage right now
              errors = errors+1;
              $display("  Error on test %s result %d: adr = %h sim = %h, signature = %h", 
                    tests[test], i, (testadr+i)*`XLEN/8, dut.uncore.dtim.RAM[testadr+i], signature[i]);
            end
          end
          i = i + 1;
        end
        /* verilator lint_on INFINITELOOP */
        if (errors == 0) $display("%s succeeded.  Brilliant!!!", tests[test]);
        else begin
          $display("%s failed with %d errors. :(", tests[test], errors);
          totalerrors = totalerrors+1;
        end
        test = test + 2;
        if (test == tests.size()) begin
          if (totalerrors == 0) $display("SUCCESS! All tests ran without failures.");
          else $display("FAIL: %d test programs had errors", totalerrors);
          $stop;
        end
        else begin
          memfilename = {"../../imperas-riscv-tests/work/", tests[test], ".elf.memfile"};
          $readmemh(memfilename, dut.imem.RAM);
          $readmemh(memfilename, dut.uncore.dtim.RAM);
          $display("Read memfile %s", memfilename);
          reset = 1; # 17; reset = 0;
        end
      end
    end
endmodule

/* verilator lint_on STMTDLY */
/* verilator lint_on WIDTH */

module instrTrackerTB(
  input  logic            clk, reset, FlushE,
  input  logic [31:0]     InstrD,
  input  logic [31:0]     InstrE, InstrM,
  output logic [31:0]     InstrW,
  output string           InstrDName, InstrEName, InstrMName, InstrWName);
        
  // stage Instr to Writeback for visualization
  flopr  #(32) InstrWReg(clk, reset, InstrM, InstrW);

  instrNameDecTB ddec(InstrD, InstrDName);
  instrNameDecTB edec(InstrE, InstrEName);
  instrNameDecTB mdec(InstrM, InstrMName);
  instrNameDecTB wdec(InstrW, InstrWName);
endmodule

// decode the instruction name, to help the test bench
module instrNameDecTB(
  input  logic [31:0] instr,
  output string       name);

  logic [6:0] op;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [11:0] imm;

  assign op = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];
  assign imm = instr[31:20];

  // it would be nice to add the operands to the name 
  // create another variable called decoded

  always_comb 
    casez({op, funct3})
      10'b0000000_000: name = "BAD";
      10'b0000011_000: name = "LB";
      10'b0000011_001: name = "LH";
      10'b0000011_010: name = "LW";
      10'b0000011_011: name = "LD";
      10'b0000011_100: name = "LBU";
      10'b0000011_101: name = "LHU";
      10'b0000011_110: name = "LWU";
      10'b0010011_000: if (instr[31:15] == 0 && instr[11:7] ==0) name = "NOP/FLUSH";
                       else                                      name = "ADDI";
      10'b0010011_001: if (funct7[6:1] == 6'b000000) name = "SLLI";
                       else                      name = "ILLEGAL";
      10'b0010011_010: name = "SLTI";
      10'b0010011_011: name = "SLTIU";
      10'b0010011_100: name = "XORI";
      10'b0010011_101: if (funct7[6:1] == 6'b000000)      name = "SRLI";
                       else if (funct7[6:1] == 6'b010000) name = "SRAI"; 
                       else                           name = "ILLEGAL"; 
      10'b0010011_110: name = "ORI";
      10'b0010011_111: name = "ANDI";
      10'b0010111_???: name = "AUIPC";
      10'b0100011_000: name = "SB";
      10'b0100011_001: name = "SH";
      10'b0100011_010: name = "SW";
      10'b0100011_011: name = "SD";
      10'b0011011_000: name = "ADDIW";
      10'b0011011_001: name = "SLLIW";
      10'b0011011_101: if      (funct7 == 7'b0000000) name = "SRLIW";
                       else if (funct7 == 7'b0100000) name = "SRAIW";
                       else                           name = "ILLEGAL";
      10'b0111011_000: if      (funct7 == 7'b0000000) name = "ADDW";
                       else if (funct7 == 7'b0100000) name = "SUBW";
                       else                           name = "ILLEGAL";
      10'b0111011_001: name = "SLLW";
      10'b0111011_101: if      (funct7 == 7'b0000000) name = "SRLW";
                       else if (funct7 == 7'b0100000) name = "SRAW";
                       else                           name = "ILLEGAL";
      10'b0110011_000: if      (funct7 == 7'b0000000) name = "ADD";
                       else if (funct7 == 7'b0000001) name = "MUL";
                       else if (funct7 == 7'b0100000) name = "SUB"; 
                       else                           name = "ILLEGAL"; 
      10'b0110011_001: if      (funct7 == 7'b0000000) name = "SLL";
                       else if (funct7 == 7'b0000001) name = "MULH";
                       else                           name = "ILLEGAL";
      10'b0110011_010: if      (funct7 == 7'b0000000) name = "SLT";
                       else if (funct7 == 7'b0000001) name = "MULHSU";
                       else                           name = "ILLEGAL";
      10'b0110011_011: if      (funct7 == 7'b0000000) name = "SLTU";
                       else if (funct7 == 7'b0000001) name = "DIV";
                       else                           name = "ILLEGAL";
      10'b0110011_100: if      (funct7 == 7'b0000000) name = "XOR";
                       else if (funct7 == 7'b0000001) name = "MUL";
                       else                           name = "ILLEGAL";
      10'b0110011_101: if      (funct7 == 7'b0000000) name = "SRL";
                       else if (funct7 == 7'b0000001) name = "DIVU";
                       else if (funct7 == 7'b0100000) name = "SRA";
                       else                           name = "ILLEGAL";
      10'b0110011_110: if      (funct7 == 7'b0000000) name = "OR";
                       else if (funct7 == 7'b0000001) name = "REM";
                       else                           name = "ILLEGAL";
      10'b0110011_111: if      (funct7 == 7'b0000000) name = "AND";
                       else if (funct7 == 7'b0000001) name = "REMU";
                       else                           name = "ILLEGAL";
      10'b0110111_???: name = "LUI";
      10'b1100011_000: name = "BEQ";
      10'b1100011_001: name = "BNE";
      10'b1100011_100: name = "BLT";
      10'b1100011_101: name = "BGE";
      10'b1100011_110: name = "BLTU";
      10'b1100011_111: name = "BGEU";
      10'b1100111_000: name = "JALR";
      10'b1101111_???: name = "JAL";
      10'b1110011_000: if      (imm == 0) name = "ECALL";
                       else if (imm == 1) name = "EBREAK";
                       else if (imm == 2) name = "URET";
                       else if (imm == 258) name = "SRET";
                       else if (imm == 770) name = "MRET";
                       else              name = "ILLEGAL";
      10'b1110011_001: name = "CSRRW";
      10'b1110011_010: name = "CSRRS";
      10'b1110011_011: name = "CSRRC";
      10'b1110011_101: name = "CSRRWI";
      10'b1110011_110: name = "CSRRSI";
      10'b1110011_111: name = "CSRRCI";
      10'b0001111_???: name = "FENCE";
      default:         name = "ILLEGAL";
    endcase
endmodule