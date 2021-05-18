
`include "wally-config.vh"
//  `include "../../config/rv64icfd/wally-config.vh" //debug

module fpu (
  //input  logic [2:0]       FrmD,
  input  logic [2:0]       FRM_REGW,    // Rounding mode from CSR
  input  logic             reset,
  //input  logic             clear,     // *** not being used anywhere
  input  logic             clk,
  input  logic [31:0]      InstrD,
  input  logic [`XLEN-1:0] SrcAE,       // Integer input being processed
  input  logic [`XLEN-1:0] SrcAM,       // Integer input being written into fpreg
  input  logic 		   StallE, StallM, StallW,
  input  logic             FlushE, FlushM, FlushW,
  output logic [4:0]       SetFflagsM,
  output logic [31:0]      FSROutW,
  output logic             DivSqrtDoneE,
  output logic             IllegalFPUInstrD,
  output logic [`XLEN-1:0] FPUResultW);

  //NOTE:
  //For readability and ease of modification, logic signals will be
  //instantiated as they occur within the pipeline. This will keep local
  //signals, modules, and combinational logic closely defined.

  //used for OSU DP-size hardware to wally XLEN interfacing

  integer XLENDIFF;
  assign XLENDIFF = `XLEN - 64;
  integer XLENDIFFN;
  assign XLENDIFFN = 63 - `XLEN;

  //#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#
  //BEGIN PIPELINE CONTROL LOGIC
  //
   
  logic	                   PipeEnableDE;
  logic	                   PipeEnableEM;
  logic	                   PipeEnableMW;
  logic                    PipeClearDE;
  logic                    PipeClearEM;
  logic                    PipeClearMW;

  //temporarily assign pipe clear and enable signals
  //to never flush & always be running
  localparam PipeClear = 1'b0;
  localparam PipeEnable = 1'b1;
  always_comb begin

	  PipeEnableDE = ~StallE;
	  PipeEnableEM = ~StallM;
	  PipeEnableMW = ~StallW;
	  PipeClearDE = FlushE;
	  PipeClearEM = FlushM;
	  PipeClearMW = FlushW;

  end

  //
  //END PIPELINE CONTROL LOGIC
  //#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#

  //#########################################
  //BEGIN DECODE STAGE
  //
 
  //wally-spec D stage control logic signal instantiation
  logic                    FRegWriteD;
  logic [2:0]              FResultSelD;
  logic [2:0]              FrmD;
  logic                    FmtD;
  logic                    DivSqrtStartD;
  logic [3:0]              OpCtrlD;
  logic                    WriteIntD;
  
  //top-level controller for FPU
  fctrl ctrl (.Funct7D(InstrD[31:25]), .OpD(InstrD[6:0]), .Rs2D(InstrD[24:20]), .Funct3D(InstrD[14:12]), .*);

  //instantiation of D stage regfile signals (includes some W stage signals
  //for easy reference)
  logic [2:0]              FrmW;
  logic                    FmtW;
  logic                    FRegWriteW;
  logic [4:0]              RdW, Rs1D, Rs2D, Rs3D;
  logic [`XLEN-1:0]        WriteDataW;
  logic [63:0] FPUResultDirW; 
  logic [`XLEN-1:0]        ReadData1D, ReadData2D, ReadData3D; 

  //regfile instantiation
  freg3adr fpregfile (FmtW, reset, PipeClear, clk, RdW, FRegWriteW, InstrD[19:15], InstrD[24:20], InstrD[31:27], FPUResultDirW, ReadData1D, ReadData2D, ReadData3D);

  //always_comb begin
  //   FrmW = InstrD[14:12];
  //end
  //
  //END DECODE STAGE
  //#########################################

  //*****************************************
  //BEGIN D/E PIPE
  //

  //wally-spec E stage control logic signal instantiation
  logic                    FRegWriteE;
  logic [2:0]              FResultSelE;
  logic [2:0]              FrmE;
  logic                    FmtE;
  logic                    DivSqrtStartE;
  logic [3:0]              OpCtrlE;

  //instantiation of E stage regfile signals
  logic [4:0]              RdE;
  logic [`XLEN-1:0]        ReadData1E, ReadData2E, ReadData3E;

  //instantiation of E/M stage div/sqrt signals
  logic                    DivSqrtDone, DivDenormM;
  logic [63:0]             DivResultM;
  logic [4:0]              DivFlagsM;
  logic [63:0]             DivOp1, DivOp2;
  logic [2:0]              DivFrm;
  logic                    DivOpType;
  logic                    DivP;
  logic                    DivOvEn, DivUnEn;
  logic                    DivStart;

  //instantiate E stage FMA signals here
  logic [12:0]		aligncntE; 
  logic [105:0]		rE; 
  logic [105:0]		sE; 
  logic [163:0]		tE;	
  logic [8:0]		normcntE; 
  logic [12:0]		aeE; 
  logic 		bsE;
  logic 		killprodE; 
  logic 		prodofE; 
  logic			xzeroE;
  logic			yzeroE;
  logic			zzeroE;
  logic			xdenormE;
  logic			ydenormE;
  logic			zdenormE;
  logic			xinfE;
  logic			yinfE;
  logic			zinfE;
  logic			xnanE;
  logic			ynanE;
  logic			znanE;
  logic			nanE;
  logic	[8:0]		sumshiftE;
  logic			sumshiftzeroE;
  logic                 prodinfE;
  
  //instantiation of E stage add/cvt signals
  logic [63:0]             AddSumE, AddSumTcE;
  logic [3:0]              AddSelInvE;
  logic [10:0]             AddExpPostSumE;
  logic                    AddCorrSignE, AddOp1NormE, AddOp2NormE, AddOpANormE, AddOpBNormE, AddInvalidE;
  logic                    AddDenormInE, AddSwapE, AddNormOvflowE, AddSignAE;
  logic                    AddConvertE;
  logic [63:0]             AddFloat1E, AddFloat2E;
  logic [11:0]             AddExp1DenormE, AddExp2DenormE;
  logic [10:0]             AddExponentE;
  logic [63:0]             AddOp1E, AddOp2E;
  logic [2:0]              AddRmE;
  logic [3:0]              AddOpTypeE;
  logic                    AddPE, AddOvEnE, AddUnEnE;  

  //instantiation of E stage cmp signals 
  logic [7:0]              WE, XE;
  logic                    ANaNE, BNaNE, AzeroE, BzeroE;
  logic [63:0]             CmpOp1E, CmpOp2E;
  logic [1:0]              CmpSelE;

  //instantiation of E/M stage fsgn signals (due to bypass logic)
  logic [63:0]             SgnOp1E, SgnOp2E;
  logic [1:0]              SgnOpCodeE, SgnOpCodeM;
  logic [63:0]             SgnResultE, SgnResultM;
  logic [4:0]              SgnFlagsE, SgnFlagsM;

  //*****************
  //fpregfile D/E pipe registers
  //*****************
  flopenrc #(64) DEReg1(clk, reset, PipeClearDE, PipeEnableDE, ReadData1D, ReadData1E);
  flopenrc #(64) DEReg2(clk, reset, PipeClearDE, PipeEnableDE, ReadData2D, ReadData2E);
  flopenrc #(64) DEReg3(clk, reset, PipeClearDE, PipeEnableDE, ReadData3D, ReadData3E);

  //*****************
  //other  D/E pipe registers
  //*****************
  flopenrc #(1) DEReg4(clk, reset, PipeClearDE, PipeEnableDE, FRegWriteD, FRegWriteE);
  flopenrc #(3) DEReg5(clk, reset, PipeClearDE, PipeEnableDE, FResultSelD, FResultSelE);
  flopenrc #(3) DEReg6(clk, reset, PipeClearDE, PipeEnableDE, FrmD, FrmE);
  flopenrc #(1) DEReg7(clk, reset, PipeClearDE, PipeEnableDE, FmtD, FmtE);
  flopenrc #(5) DEReg8(clk, reset, PipeClearDE, PipeEnableDE, InstrD[11:7], RdE);
  flopenrc #(4) DEReg9(clk, reset, PipeClearDE, PipeEnableDE, OpCtrlD, OpCtrlE);
  flopenrc #(1) DEReg10(clk, reset, PipeClearDE, PipeEnableDE, DivSqrtStartD, DivSqrtStartE);

  //
  //END D/E PIPE
  //*****************************************

  //#########################################
  //BEGIN EXECUTION STAGE
  //

  fma1 fma1 (.*);

  //first and only instance of floating-point divider
  fpdiv fpdivsqrt (.*);

  //first of two-stage instance of floating-point add/cvt unit
  fpuaddcvt1 fpadd1 (AddSumE, AddSumTcE, AddSelInvE, AddExpPostSumE, AddCorrSignE, AddOp1NormE, AddOp2NormE, AddOpANormE, AddOpBNormE, AddInvalidE, AddDenormInE, AddConvertE, AddSwapE, AddNormOvflowE, AddSignAE, AddFloat1E, AddFloat2E, AddExp1DenormE, AddExp2DenormE, AddExponentE, ReadData1E, ReadData2E, FrmE, OpCtrlE, FmtE);

  //first of two-stage instance of floating-point comparator
  fpucmp1 fpcmp1 (WE, XE, ANaNE, BNaNE, AzeroE, BzeroE, ReadData1E, ReadData2E, OpCtrlE[1:0]);

  //first and only instance of floating-point sign converter
  fpusgn fpsgn (.*);

  //interface between XLEN size datapath and double-precision sized
  //floating-point results
  //
  //define offsets for LSB zero extension or truncation
  always_comb begin

  //truncate to 64 bits
  //(causes warning during compilation - case never reached) 
//   if(`XLEN > 64) begin // ***KEP this isn't usedand it causes a lint error
//         DivOp1 = ReadData1E[`XLEN-1:`XLEN-64];
// 	DivOp2 = ReadData2E[`XLEN-1:`XLEN-64];
//         AddOp1E = ReadData1E[`XLEN-1:`XLEN-64];
// 	AddOp2E = ReadData2E[`XLEN-1:`XLEN-64];
//         CmpOp1E = ReadData1E[`XLEN-1:`XLEN-64];
// 	CmpOp2E = ReadData2E[`XLEN-1:`XLEN-64];
//         SgnOp1E = ReadData1E[`XLEN-1:`XLEN-64];
// 	SgnOp2E = ReadData2E[`XLEN-1:`XLEN-64];
//   end
//   //zero extend to 64 bits
//   else begin
//         DivOp1 = {ReadData1E,{64-`XLEN{1'b0}}};
// 	DivOp2 = {ReadData2E,{64-`XLEN{1'b0}}};
//         AddOp1E = {ReadData1E,{64-`XLEN{1'b0}}};
// 	AddOp2E = {ReadData2E,{64-`XLEN{1'b0}}};
//         CmpOp1E = {ReadData1E,{64-`XLEN{1'b0}}};
// 	CmpOp2E = {ReadData2E,{64-`XLEN{1'b0}}};
//         SgnOp1E = {ReadData1E,{64-`XLEN{1'b0}}};
// 	SgnOp2E = {ReadData2E,{64-`XLEN{1'b0}}};
//   end

  //assign op codes
  AddOpTypeE[3:0] = OpCtrlE[3:0];
  CmpSelE[1:0] = OpCtrlE[1:0];
  DivOpType = OpCtrlE[0];
  SgnOpCodeE[1:0] = OpCtrlE[1:0];

  end 

  //E stage control signal interfacing between wally spec and OSU fp hardware
  //op codes

  //
  //END EXECUTION STAGE
  //#########################################

  //*****************************************
  //BEGIN E/M PIPE
  //

  //wally-spec M stage control logic signal instantiation
  logic                    FRegWriteM;
  logic [2:0]              FResultSelM;
  logic [2:0]              FrmM;
  logic                    FmtM;
  logic [3:0]              OpCtrlM;

  //instantiate M stage FMA signals here ***rename fma signals and resize for XLEN
  logic [63:0]		FmaResultM;
  logic [4:0]	 	FmaFlagsM;
  logic [12:0]		aligncntM; 
  logic [105:0]		rM; 
  logic [105:0]		sM; 
  logic [163:0]		tM;	
  logic [8:0]		normcntM; 
  logic [12:0]		aeM; 
  logic 		bsM;
  logic 		killprodM; 
  logic 		prodofM; 
  logic			xzeroM;
  logic			yzeroM;
  logic			zzeroM;
  logic			xdenormM;
  logic			ydenormM;
  logic			zdenormM;
  logic			xinfM;
  logic			yinfM;
  logic			zinfM;
  logic			xnanM;
  logic			ynanM;
  logic			znanM;
  logic			nanM;
  logic	[8:0]		sumshiftM;
  logic			sumshiftzeroM;
  logic                 prodinfM;

  //instantiation of M stage regfile signals
  logic [4:0]              RdM;
  logic [`XLEN-1:0]        ReadData1M, ReadData2M, ReadData3M;

  //instantiation of M stage add/cvt signals
  logic [63:0]             AddResultM;
  logic [4:0]              AddFlagsM;
  logic                    AddDenormM;
  logic [63:0]             AddSumM, AddSumTcM;
  logic [3:0]              AddSelInvM;
  logic [10:0]             AddExpPostSumM;
  logic                    AddCorrSignM, AddOp1NormM, AddOp2NormM, AddOpANormM, AddOpBNormM, AddInvalidM;
  logic                    AddDenormInM, AddSwapM, AddNormOvflowM, AddSignAM;
  logic                    AddConvertM, AddSignM;
  logic [63:0]             AddFloat1M, AddFloat2M;
  logic [11:0]             AddExp1DenormM, AddExp2DenormM;
  logic [10:0]             AddExponentM;
  logic [63:0]             AddOp1M, AddOp2M;
  logic [2:0]              AddRmM;
  logic [3:0]              AddOpTypeM;
  logic                    AddPM, AddOvEnM, AddUnEnM;  

  //instantiation of M stage cmp signals
  logic                    CmpInvalidM;
  logic [1:0]              CmpFCCM; 
  logic [7:0]              WM, XM;
  logic                    ANaNM, BNaNM, AzeroM, BzeroM;
  logic [63:0]             CmpOp1M, CmpOp2M;
  logic [1:0]              CmpSelM;

  //*****************
  //fma E/M pipe registers
  //*****************  
  flopenrc #(13) EMRegFma1(clk, reset, PipeClearEM, PipeEnableEM, aligncntE, aligncntM); 
  flopenrc #(106) EMRegFma2(clk, reset, PipeClearEM, PipeEnableEM, rE, rM); 
  flopenrc #(106) EMRegFma3(clk, reset, PipeClearEM, PipeEnableEM, sE, sM); 
  flopenrc #(164) EMRegFma4(clk, reset, PipeClearEM, PipeEnableEM, tE, tM); 
  flopenrc #(9) EMRegFma5(clk, reset, PipeClearEM, PipeEnableEM, normcntE, normcntM); 
  flopenrc #(13) EMRegFma6(clk, reset, PipeClearEM, PipeEnableEM, aeE, aeM);  
  flopenrc #(1) EMRegFma7(clk, reset, PipeClearEM, PipeEnableEM, bsE, bsM); 
  flopenrc #(1) EMRegFma8(clk, reset, PipeClearEM, PipeEnableEM, killprodE, killprodM); 
  flopenrc #(1) EMRegFma9(clk, reset, PipeClearEM, PipeEnableEM, prodofE, prodofM); 
  flopenrc #(1) EMRegFma10(clk, reset, PipeClearEM, PipeEnableEM, xzeroE, xzeroM); 
  flopenrc #(1) EMRegFma11(clk, reset, PipeClearEM, PipeEnableEM, yzeroE, yzeroM); 
  flopenrc #(1) EMRegFma12(clk, reset, PipeClearEM, PipeEnableEM, zzeroE, zzeroM); 
  flopenrc #(1) EMRegFma13(clk, reset, PipeClearEM, PipeEnableEM, xdenormE, xdenormM); 
  flopenrc #(1) EMRegFma14(clk, reset, PipeClearEM, PipeEnableEM, ydenormE, ydenormM); 
  flopenrc #(1) EMRegFma15(clk, reset, PipeClearEM, PipeEnableEM, zdenormE, zdenormM); 
  flopenrc #(1) EMRegFma16(clk, reset, PipeClearEM, PipeEnableEM, xinfE, xinfM); 
  flopenrc #(1) EMRegFma17(clk, reset, PipeClearEM, PipeEnableEM, yinfE, yinfM); 
  flopenrc #(1) EMRegFma18(clk, reset, PipeClearEM, PipeEnableEM, zinfE, zinfM); 
  flopenrc #(1) EMRegFma19(clk, reset, PipeClearEM, PipeEnableEM, xnanE, xnanM); 
  flopenrc #(1) EMRegFma20(clk, reset, PipeClearEM, PipeEnableEM, ynanE, ynanM); 
  flopenrc #(1) EMRegFma21(clk, reset, PipeClearEM, PipeEnableEM, znanE, znanM); 
  flopenrc #(1) EMRegFma22(clk, reset, PipeClearEM, PipeEnableEM, nanE, nanM); 
  flopenrc #(9) EMRegFma23(clk, reset, PipeClearEM, PipeEnableEM, sumshiftE, sumshiftM); 
  flopenrc #(1) EMRegFma24(clk, reset, PipeClearEM, PipeEnableEM, sumshiftzeroE, sumshiftzeroM); 
  flopenrc #(1) EMRegFma25(clk, reset, PipeClearEM, PipeEnableEM, prodinfE, prodinfM); 

  //*****************
  //fpadd E/M pipe registers
  //*****************
  flopenrc #(64) EMRegAdd1(clk, reset, PipeClearEM, PipeEnableEM, AddSumE, AddSumM); 
  flopenrc #(64) EMRegAdd2(clk, reset, PipeClearEM, PipeEnableEM, AddSumTcE, AddSumTcM); 
  flopenrc #(4)  EMRegAdd3(clk, reset, PipeClearEM, PipeEnableEM, AddSelInvE, AddSelInvM); 
  flopenrc #(11) EMRegAdd4(clk, reset, PipeClearEM, PipeEnableEM, AddExpPostSumE, AddExpPostSumM); 
  flopenrc #(1) EMRegAdd5(clk, reset, PipeClearEM, PipeEnableEM, AddCorrSignE, AddCorrSignM); 
  flopenrc #(1) EMRegAdd6(clk, reset, PipeClearEM, PipeEnableEM, AddOp1NormE, AddOp1NormM); 
  flopenrc #(1) EMRegAdd7(clk, reset, PipeClearEM, PipeEnableEM, AddOp2NormE, AddOp2NormM); 
  flopenrc #(1) EMRegAdd8(clk, reset, PipeClearEM, PipeEnableEM, AddOpANormE, AddOpANormM); 
  flopenrc #(1) EMRegAdd9(clk, reset, PipeClearEM, PipeEnableEM, AddOpBNormE, AddOpBNormM); 
  flopenrc #(1) EMRegAdd10(clk, reset, PipeClearEM, PipeEnableEM, AddInvalidE, AddInvalidM); 
  flopenrc #(1) EMRegAdd11(clk, reset, PipeClearEM, PipeEnableEM, AddDenormInE, AddDenormInM); 
  flopenrc #(1) EMRegAdd12(clk, reset, PipeClearEM, PipeEnableEM, AddConvertE, AddConvertM); 
  flopenrc #(1) EMRegAdd13(clk, reset, PipeClearEM, PipeEnableEM, AddSwapE, AddSwapM); 
  flopenrc #(1) EMRegAdd14(clk, reset, PipeClearEM, PipeEnableEM, AddNormOvflowE, AddNormOvflowM); 
  flopenrc #(1) EMRegAdd15(clk, reset, PipeClearEM, PipeEnableEM, AddSignAE, AddSignM); 
  flopenrc #(64) EMRegAdd16(clk, reset, PipeClearEM, PipeEnableEM, AddFloat1E, AddFloat1M); 
  flopenrc #(64) EMRegAdd17(clk, reset, PipeClearEM, PipeEnableEM, AddFloat2E, AddFloat2M); 
  flopenrc #(12) EMRegAdd18(clk, reset, PipeClearEM, PipeEnableEM, AddExp1DenormE, AddExp1DenormM); 
  flopenrc #(12) EMRegAdd19(clk, reset, PipeClearEM, PipeEnableEM, AddExp2DenormE, AddExp2DenormM); 
  flopenrc #(11) EMRegAdd20(clk, reset, PipeClearEM, PipeEnableEM, AddExponentE, AddExponentM); 
  flopenrc #(64) EMRegAdd21(clk, reset, PipeClearEM, PipeEnableEM, AddOp1E, AddOp1M); 
  flopenrc #(64) EMRegAdd22(clk, reset, PipeClearEM, PipeEnableEM, AddOp2E, AddOp2M); 
  flopenrc #(3) EMRegAdd23(clk, reset, PipeClearEM, PipeEnableEM, AddRmE, AddRmM); 
  flopenrc #(4) EMRegAdd24(clk, reset, PipeClearEM, PipeEnableEM, AddOpTypeE, AddOpTypeM); 
  flopenrc #(1) EMRegAdd25(clk, reset, PipeClearEM, PipeEnableEM, AddPE, AddPM); 
  flopenrc #(1) EMRegAdd26(clk, reset, PipeClearEM, PipeEnableEM, AddOvEnE, AddOvEnM); 
  flopenrc #(1) EMRegAdd27(clk, reset, PipeClearEM, PipeEnableEM, AddUnEnE, AddUnEnM); 

  //*****************
  //fpcmp E/M pipe registers
  //*****************
  flopenrc #(8) EMRegCmp1(clk, reset, PipeClearEM, PipeEnableEM, WE, WM); 
  flopenrc #(8) EMRegCmp2(clk, reset, PipeClearEM, PipeEnableEM, XE, XM); 
  flopenrc #(1) EMRegcmp3(clk, reset, PipeClearEM, PipeEnableEM, ANaNE, ANaNM); 
  flopenrc #(1) EMRegCmp4(clk, reset, PipeClearEM, PipeEnableEM, BNaNE, BNaNM); 
  flopenrc #(1) EMRegCmp5(clk, reset, PipeClearEM, PipeEnableEM, AzeroE, AzeroM); 
  flopenrc #(1) EMRegCmp6(clk, reset, PipeClearEM, PipeEnableEM, BzeroE, BzeroM); 
  flopenrc #(64) EMRegCmp7(clk, reset, PipeClearEM, PipeEnableEM, CmpOp1E, CmpOp1M); 
  flopenrc #(64) EMRegCmp8(clk, reset, PipeClearEM, PipeEnableEM, CmpOp2E, CmpOp2M); 
  flopenrc #(2) EMRegCmp9(clk, reset, PipeClearEM, PipeEnableEM, CmpSelE, CmpSelM);

  //put this in for the event we want to delay fsgn - will otherwise bypass
  //*****************
  //fpsgn E/M pipe registers
  //***************** 
  flopenrc #(2) EMRegSgn1(clk, reset, PipeClearEM, PipeEnableEM, SgnOpCodeE, SgnOpCodeM);
  flopenrc #(64) EMRegSgn2(clk, reset, PipeClearEM, PipeEnableEM, SgnResultE, SgnResultM);
  flopenrc #(5) EMRegSgn3(clk, reset, PipeClearEM, PipeEnableEM, SgnFlagsE, SgnFlagsM);

  //*****************
  //other E/M pipe registers
  //*****************
  flopenrc #(1) EMReg1(clk, reset, PipeClearEM, PipeEnableEM, FRegWriteE, FRegWriteM);
  flopenrc #(3) EMReg2(clk, reset, PipeClearEM, PipeEnableEM, FResultSelE, FResultSelM);
  flopenrc #(3) EMReg3(clk, reset, PipeClearEM, PipeEnableEM, FrmE, FrmM);
  flopenrc #(1) EMReg4(clk, reset, PipeClearEM, PipeEnableEM, FmtE, FmtM);
  flopenrc #(5) EMReg5(clk, reset, PipeClearEM, PipeEnableEM, RdE, RdM);
  flopenrc #(4) EMReg6(clk, reset, PipeClearEM, PipeEnableEM, OpCtrlE, OpCtrlM);

  //
  //END E/M PIPE
  //*****************************************

  //#########################################
  //BEGIN MEMORY STAGE
  //

  fma2 fma2(.*);

  //second instance of two-stage floating-point add/cvt unit
  fpuaddcvt2 fpadd2 (.*);

  //second instance of two-stage floating-point comparator
  fpucmp2 fpcmp2 (CmpInvalidM, CmpFCCM, ANaNM, BNaNM, AzeroM, BzeroM, WM, XM, CmpSelM, CmpOp1M, CmpOp2M);

  //
  //END MEMORY STAGE
  //#########################################


  //*****************************************
  //BEGIN M/W PIPE
  //
  
  //wally-spec W stage control logic signal instantiation
  logic [2:0]              FResultSelW;

  //instantiate W stage fma signals here
  logic [63:0]             FmaResultW;
  logic [4:0]              FmaFlagsW;

  //instantiation of W stage div/sqrt signals
  logic                    DivDenormW;
  logic [63:0]             DivResultW;
  logic [4:0]              DivFlagsW;

  //instantiation of W stage fsgn signals
  logic [63:0]            SgnResultW;
  logic [4:0]             SgnFlagsW;

  //instantiation of W stage regfile signals
  logic [`XLEN-1:0]        ReadData1W, ReadData2W, ReadData3W;
  logic [`XLEN-1:0]        SrcAW;

  //instantiation of W stage add/cvt signals
  logic [63:0]             AddResultW;
  logic [4:0]              AddFlagsW;
  logic                    AddDenormW;

  //instantiation of W stage cmp signals
  logic [63:0]             CmpResultW;
  logic                    CmpInvalidW;
  logic [1:0]              CmpFCCW; 

  //instantiation of W stage classify signals
  logic [63:0]             ClassResultW;
  logic [4:0]              ClassFlagsW;

  //*****************
  //fma M/W pipe registers
  //*****************
  flopenrc #(64) MWRegFma1(clk, reset, PipeClearMW, PipeEnableMW, FmaResultM, FmaResultW); 
  flopenrc #(5) MWRegFma2(clk, reset, PipeClearMW, PipeEnableMW, FmaFlagsM, FmaFlagsW); 

  //*****************
  //fpdiv M/W pipe registers
  //*****************
  flopenrc #(64) MWRegDiv1(clk, reset, PipeClearMW, PipeEnableMW, DivResultM, DivResultW); 
  flopenrc #(5) MWRegDiv2(clk, reset, PipeClearMW, PipeEnableMW, DivFlagsM, DivFlagsW);
  flopenrc #(1) MWRegDiv3(clk, reset, PipeClearMW, PipeEnableMW, DivDenormM, DivDenormW); 

  //*****************
  //fpadd M/W pipe registers
  //*****************
  flopenrc #(64) MWRegAdd1(clk, reset, PipeClearMW, PipeEnableMW, AddResultM, AddResultW); 
  flopenrc #(5) MWRegAdd2(clk, reset, PipeClearMW, PipeEnableMW, AddFlagsM, AddFlagsW); 
  flopenrc #(1) MWRegAdd3(clk, reset, PipeClearMW, PipeEnableMW, AddDenormM, AddDenormW); 

  //*****************
  //fpcmp M/W pipe registers
  //*****************
  flopenrc #(1) MWRegCmp1(clk, reset, PipeClearMW, PipeEnableMW, CmpInvalidM, CmpInvalidW); 
  flopenrc #(2) MWRegCmp2(clk, reset, PipeClearMW, PipeEnableMW, CmpFCCM, CmpFCCW); 

  //*****************
  //fpsgn M/W pipe registers
  //***************** 
  flopenrc #(64) MWRegSgn1(clk, reset, PipeClearMW, PipeEnableMW, SgnResultM, SgnResultW);
  flopenrc #(5) MWRegSgn2(clk, reset, PipeClearMW, PipeEnableMW, SgnFlagsM, SgnFlagsW);

  //*****************
  //other M/W pipe registers
  //*****************
  flopenrc #(1) MWReg1(clk, reset, PipeClearMW, PipeEnableMW, FRegWriteM, FRegWriteW);
  flopenrc #(3) MWReg2(clk, reset, PipeClearMW, PipeEnableMW, FResultSelM, FResultSelW);
  flopenrc #(1) MWReg3(clk, reset, PipeClearMW, PipeEnableMW, FmtM, FmtW);
  flopenrc #(5) MWReg4(clk, reset, PipeClearMW, PipeEnableMW, RdM, RdW);
  flopenrc #(`XLEN) MWReg5(clk, reset, PipeClearMW, PipeEnableMW, SrcAM, SrcAW);

  ////END M/W PIPE
  //*****************************************


  //#########################################
  //BEGIN WRITEBACK STAGE
  //

  //flag signal mux via in-line ternaries
  logic [4:0] FPUFlagsW;
  //if bit 2 is active set to sign flags - otherwise:
  //iff bit one is high - if bit zero is active set to fma flags - otherwise
  //set to cmp flags
  //iff bit one is low - if bit zero is active set to add/cvt flags - otherwise
  //set to div/sqrt flags
  //assign FPUFlagsW = (FResultSelW[2]) ? (SgnFlagsW) : (
//	             (FResultSelW[1]) ? 
//		     ( (FResultSelW[0]) ? (FmaFlagsW) : ({CmpInvalidW,4'b0000}) ) 
//		     : ( (FResultSelW[0]) ? (AddFlagsW) : (DivFlagsW) ) 
//                     );
  always_comb begin
	case (FResultSelW)
		// div/sqrt
		3'b000 : FPUFlagsW = DivFlagsW;
		// cmp		
		3'b001 : FPUFlagsW = {CmpInvalidW, 4'b0};
		//fma/mult
		3'b010 : FPUFlagsW = FmaFlagsW;
		// sgn inj
		3'b011 : FPUFlagsW = SgnFlagsW;
		// add/sub/cnvt
		3'b100 : FPUFlagsW = AddFlagsW;
		// classify
		3'b101 : FPUFlagsW = ClassFlagsW;
		// output SrcAW
		3'b110 : FPUFlagsW = 5'b0;
		// output ReadData1
		3'b111 : FPUFlagsW = 5'b0;
		default : FPUFlagsW = 5'bxxxxx;
	endcase
  end

  //result mux via in-line ternaries
  //the uses the same logic as for flag signals
  //assign FPUResultDirW = (FResultSelW[2]) ? (SgnResultW) : (
  //	             (FResultSelW[1]) ? 
  //		     ( (FResultSelW[0]) ? (FmaResultW) : ({62'b0,CmpFCCW}) ) 
  //		     : ( (FResultSelW[0]) ? (AddResultW) : (DivResultW) ) 
  //                   );
  always_comb begin
	case (FResultSelW)
		// div/sqrt
		3'b000 : FPUResultDirW = DivResultW;
		// cmp		
		3'b001 : FPUResultDirW = CmpResultW;
		//fma/mult
		3'b010 : FPUResultDirW = FmaResultW;
		// sgn inj
		3'b011 : FPUResultDirW = SgnResultW;
		// add/sub/cnvt
		3'b100 : FPUResultDirW = AddResultW;
		// classify
		3'b101 : FPUResultDirW = ClassResultW;
		// output SrcAW
		3'b110 : FPUResultDirW = SrcAW;
		// output ReadData1
		3'b111 : FPUResultDirW = ReadData1W;
		default : FPUResultDirW = {64{1'bx}};
	endcase
  end
  //interface between XLEN size datapath and double-precision sized
  //floating-point results
  //
  //define offsets for LSB zero extension or truncation
  always_comb begin
           
  //zero extension  

// Teo 04/13/2021
// Commented out XLENDIFF{1'b0} due to error:
// Repetition multiplier must be constant.

  //if(`XLEN > 64) begin
  //    FPUResultW = {FPUResultDirW,{XLENDIFF{1'b0}}};
  //end
  //truncate
  //else begin
      FPUResultW = FPUResultDirW[63:64-`XLEN];
      SetFflagsM = FPUFlagsW;
  //end

  end  

  //
  //END WRITEBACK STAGE
  //#########################################



endmodule
