module adder4 (
	A,
	B,
	CI,
	S,
	CO
);
	input [3:0] A;
	input [3:0] B;
	input CI;
	output wire [3:0] S;
	output wire CO;
	wire CO0;
	wire CO1;
	wire CO2;
	bit_adder b_add0(
		.A(A[0]),
		.B(B[0]),
		.CI(CI),
		.S(S[0]),
		.CO(CO0)
	);
	bit_adder b_add1(
		.A(A[1]),
		.B(B[1]),
		.CI(CO0),
		.S(S[1]),
		.CO(CO1)
	);
	bit_adder b_add2(
		.A(A[2]),
		.B(B[2]),
		.CI(CO1),
		.S(S[2]),
		.CO(CO2)
	);
	bit_adder b_add3(
		.A(A[3]),
		.B(B[3]),
		.CI(CO2),
		.S(S[3]),
		.CO(CO)
	);
endmodule
module AddrGen (
	CLK,
	RST_N,
	EN,
	LOAD_PC,
	PCDec,
	GotInterrupt,
	ADDR_CTRL,
	IND_CTRL,
	D_IN,
	X,
	Y,
	D,
	S,
	T,
	DR,
	DBR,
	e6502,
	PC,
	AA,
	AB,
	DX,
	AALCarry,
	JumpNoOfl
);
	input CLK;
	input RST_N;
	input EN;
	input [2:0] LOAD_PC;
	input PCDec;
	input GotInterrupt;
	input [7:0] ADDR_CTRL;
	input [1:0] IND_CTRL;
	input [7:0] D_IN;
	input [15:0] X;
	input [15:0] Y;
	input [15:0] D;
	input [15:0] S;
	input [15:0] T;
	input [7:0] DR;
	input [7:0] DBR;
	input e6502;
	output wire [15:0] PC;
	output wire [16:0] AA;
	output reg [7:0] AB;
	output wire [15:0] DX;
	output wire AALCarry;
	output wire JumpNoOfl;
	reg [7:0] AAL;
	reg [7:0] AAH;
	reg [7:0] DL;
	reg [7:0] DH;
	reg SavedCarry;
	reg AAHCarry;
	reg [8:0] NewAAL;
	reg [8:0] NewAAH;
	wire [8:0] NewAAHWithCarry;
	wire [8:0] NewDL;
	wire [15:0] InnerDS;
	reg [15:0] PCr;
	reg [15:0] PCOffset;
	reg [15:0] NextPC;
	wire [15:0] NewPCWithOffset;
	wire [15:0] NewPCWithOffset16;
	wire [2:0] AALCtrl;
	wire [2:0] AAHCtrl;
	wire [1:0] ABSCtrl;
	assign NewPCWithOffset16 = PCr + PCOffset;
	assign NewPCWithOffset = PCr + {{8 {DR[7]}}, DR};
	always @(*)
		case (LOAD_PC)
			3'b000: NextPC = PCr;
			3'b001:
				if (GotInterrupt == 1'b0)
					NextPC = PCr + 16'd1;
				else
					NextPC = PCr;
			3'b010: NextPC = {D_IN, DR};
			3'b011: NextPC = NewPCWithOffset16;
			3'b100: NextPC = NewPCWithOffset;
			3'b101: NextPC = NewPCWithOffset16;
			3'b110: NextPC = {AAH, AAL};
			3'b111:
				if (PCDec == 1'b1)
					NextPC = PCr - 16'd3;
				else
					NextPC = PCr;
			default: NextPC = PCr;
		endcase
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			PCr <= 16'b0000000000000000;
			PCOffset <= 16'b0000000000000000;
		end
		else if (EN == 1'b1) begin
			PCOffset <= {D_IN, DR};
			PCr <= NextPC;
		end
	assign JumpNoOfl = ((~(PCr[8] ^ NewPCWithOffset[8]) & ~LOAD_PC[0]) & ~LOAD_PC[1]) & LOAD_PC[2];
	assign AALCtrl = ADDR_CTRL[7:5];
	assign AAHCtrl = ADDR_CTRL[4:2];
	assign ABSCtrl = ADDR_CTRL[1:0];
	always @(*) begin
		case (IND_CTRL)
			2'b00:
				if (AALCtrl[2] == 1'b0)
					NewAAL = {1'b0, AAL} + {1'b0, X[7:0]};
				else
					NewAAL = {1'b0, DL} + {1'b0, X[7:0]};
			2'b01:
				if (AALCtrl[2] == 1'b0)
					NewAAL = {1'b0, AAL} + {1'b0, Y[7:0]};
				else
					NewAAL = {1'b0, DL} + {1'b0, Y[7:0]};
			2'b10: NewAAL = {1'b0, X[7:0]};
			2'b11: NewAAL = {1'b0, Y[7:0]};
			default:
				;
		endcase
		if (e6502 == 1'b0)
			case (IND_CTRL)
				2'b00:
					if (AAHCtrl[2] == 1'b0)
						NewAAH = {1'b0, AAH} + {1'b0, X[15:8]};
					else
						NewAAH = ({1'b0, DH} + {1'b0, X[15:8]}) + {8'b00000000, NewAAL[8]};
				2'b01:
					if (AAHCtrl[2] == 1'b0)
						NewAAH = {1'b0, AAH} + {1'b0, Y[15:8]};
					else
						NewAAH = ({1'b0, DH} + {1'b0, Y[15:8]}) + {8'b00000000, NewAAL[8]};
				2'b10: NewAAH = {1'b0, X[15:8]};
				2'b11: NewAAH = {1'b0, Y[15:8]};
				default:
					;
			endcase
		else if (AAHCtrl[2] == 1'b0)
			NewAAH = {1'b0, AAH};
		else
			NewAAH = {1'b0, DH};
	end
	assign InnerDS = ((ABSCtrl == 2'b11) & ((AALCtrl[2] == 1'b1) | (AAHCtrl[2] == 1'b1)) ? S : (e6502 == 1'b0 ? D : {D[15:8], 8'h00}));
	assign NewDL = {1'b0, InnerDS[7:0]} + {1'b0, D_IN};
	assign NewAAHWithCarry = NewAAH + {8'b00000000, SavedCarry};
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			AAL <= 8'd0;
			AAH <= 8'd0;
			AB <= 8'd0;
			DL <= 8'd0;
			DH <= 8'd0;
			AAHCarry <= 1'b0;
			SavedCarry <= 1'b0;
		end
		else if (EN == 1'b1) begin
			case (AALCtrl)
				3'b000: begin
					if (IND_CTRL[1] == 1'b1)
						AAL <= NewAAL[7:0];
					SavedCarry <= 1'b0;
				end
				3'b001: begin
					AAL <= NewAAL[7:0];
					SavedCarry <= NewAAL[8];
				end
				3'b010: begin
					AAL <= D_IN;
					SavedCarry <= 1'b0;
				end
				3'b011: begin
					AAL <= NewPCWithOffset16[7:0];
					SavedCarry <= 1'b0;
				end
				3'b100: begin
					DL <= NewAAL[7:0];
					SavedCarry <= NewAAL[8];
				end
				3'b101: begin
					DL <= NewDL[7:0];
					SavedCarry <= NewDL[8];
				end
				3'b111:
					;
				default:
					;
			endcase
			case (AAHCtrl)
				3'b000:
					if (IND_CTRL[1] == 1'b1) begin
						AAH <= NewAAH[7:0];
						AAHCarry <= 1'b0;
					end
				3'b001: begin
					AAH <= NewAAHWithCarry[7:0];
					AAHCarry <= NewAAHWithCarry[8];
				end
				3'b010: begin
					AAH <= D_IN;
					AAHCarry <= 1'b0;
				end
				3'b011: begin
					AAH <= NewPCWithOffset16[15:8];
					AAHCarry <= 1'b0;
				end
				3'b100: begin
					DH <= NewAAH[7:0];
					AAHCarry <= 1'b0;
				end
				3'b101: begin
					DH <= InnerDS[15:8];
					AAHCarry <= 1'b0;
				end
				3'b110: begin
					DH <= DH + {7'b0000000, SavedCarry};
					AAHCarry <= 1'b0;
				end
				3'b111:
					;
				default:
					;
			endcase
			case (ABSCtrl)
				2'b00:
					;
				2'b01: AB <= D_IN;
				2'b10: AB <= D_IN + {7'b0000000, NewAAHWithCarry[8]};
				2'b11:
					if ((AALCtrl[2] == 1'b0) & (AAHCtrl[2] == 1'b0))
						AB <= DBR;
				default:
					;
			endcase
		end
	assign AALCarry = NewAAL[8];
	assign AA = {AAHCarry, AAH, AAL};
	assign DX = {DH, DL};
	assign PC = PCr;
endmodule
module AddSubBCD (
	A,
	B,
	CI,
	ADD,
	BCD,
	w16,
	S,
	CO,
	VO
);
	input [15:0] A;
	input [15:0] B;
	input CI;
	input ADD;
	input BCD;
	input w16;
	output wire [15:0] S;
	output wire CO;
	output wire VO;
	wire VO1;
	wire VO3;
	wire CO0;
	wire CO1;
	wire CO2;
	wire CO3;
	BCDAdder add0(
		.A(A[3:0]),
		.B(B[3:0]),
		.CI(CI),
		.S(S[3:0]),
		.CO(CO0),
		.VO(),
		.ADD(ADD),
		.BCD(BCD)
	);
	BCDAdder add1(
		.A(A[7:4]),
		.B(B[7:4]),
		.CI(CO0),
		.S(S[7:4]),
		.CO(CO1),
		.VO(VO1),
		.ADD(ADD),
		.BCD(BCD)
	);
	BCDAdder add2(
		.A(A[11:8]),
		.B(B[11:8]),
		.CI(CO1),
		.S(S[11:8]),
		.CO(CO2),
		.VO(),
		.ADD(ADD),
		.BCD(BCD)
	);
	BCDAdder add3(
		.A(A[15:12]),
		.B(B[15:12]),
		.CI(CO2),
		.S(S[15:12]),
		.CO(CO3),
		.VO(VO3),
		.ADD(ADD),
		.BCD(BCD)
	);
	assign VO = (w16 == 1'b0 ? VO1 : VO3);
	assign CO = (w16 == 1'b0 ? CO1 : CO3);
endmodule
module ALU (
	L,
	R,
	CTRL,
	w16,
	BCD,
	CI,
	VI,
	SI,
	CO,
	VO,
	SO,
	ZO,
	RES,
	IntR
);
	input [15:0] L;
	input [15:0] R;
	input wire [7:0] CTRL;
	input w16;
	input BCD;
	input CI;
	input VI;
	input SI;
	output reg CO;
	output reg VO;
	output reg SO;
	output wire ZO;
	output wire [15:0] RES;
	output wire [15:0] IntR;
	reg [15:0] IntR16;
	reg [7:0] IntR8;
	reg CR8;
	reg CR16;
	wire CR;
	reg ZR;
	wire CIIn;
	wire ADDIn;
	wire BCDIn;
	wire [15:0] AddR;
	wire AddCO;
	wire AddVO;
	reg [15:0] Result16;
	reg [7:0] Result8;
	always @(*) begin
		CR8 = CI;
		CR16 = CI;
		case (CTRL[7-:3])
			3'b000: begin
				CR8 = R[7];
				CR16 = R[15];
				IntR8 = {R[6:0], 1'b0};
				IntR16 = {R[14:0], 1'b0};
			end
			3'b001: begin
				CR8 = R[7];
				CR16 = R[15];
				IntR8 = {R[6:0], CI};
				IntR16 = {R[14:0], CI};
			end
			3'b010: begin
				CR8 = R[0];
				CR16 = R[0];
				IntR8 = {1'b0, R[7:1]};
				IntR16 = {1'b0, R[15:1]};
			end
			3'b011: begin
				CR8 = R[0];
				CR16 = R[0];
				IntR8 = {CI, R[7:1]};
				IntR16 = {CI, R[15:1]};
			end
			3'b100: begin
				IntR8 = R[7:0];
				IntR16 = R;
			end
			3'b101: begin
				IntR8 = R[15:8];
				IntR16 = {R[7:0], R[15:8]};
			end
			3'b110: begin
				IntR8 = R[7:0] - 8'd1;
				IntR16 = R - 16'd1;
			end
			3'b111: begin
				IntR8 = R[7:0] + 8'd1;
				IntR16 = R + 16'd1;
			end
			default:
				;
		endcase
	end
	assign CR = (w16 == 1'b0 ? CR8 : CR16);
	assign CIIn = CR | ~CTRL[2];
	assign ADDIn = ~CTRL[4];
	assign BCDIn = BCD & CTRL[2];
	AddSubBCD AddSub(
		.A(L),
		.B(R),
		.CI(CIIn),
		.ADD(ADDIn),
		.BCD(BCDIn),
		.w16(w16),
		.S(AddR),
		.CO(AddCO),
		.VO(AddVO)
	);
	always @(*) begin : xhdl0
		reg [7:0] temp8;
		reg [15:0] temp16;
		ZR = 1'b0;
		temp8 = 8'b00000000;
		temp16 = 16'b0000000000000000;
		case (CTRL[4-:3])
			3'b000: begin
				CO = CR;
				Result8 = L[7:0] | IntR8;
				Result16 = L | IntR16;
			end
			3'b001: begin
				CO = CR;
				Result8 = L[7:0] & IntR8;
				Result16 = L & IntR16;
			end
			3'b010: begin
				CO = CR;
				Result8 = L[7:0] ^ IntR8;
				Result16 = L ^ IntR16;
			end
			3'b011, 3'b110, 3'b111: begin
				CO = AddCO;
				Result8 = AddR[7:0];
				Result16 = AddR;
			end
			3'b100: begin
				CO = CR;
				Result8 = IntR8;
				Result16 = IntR16;
			end
			3'b101: begin
				CO = CR;
				if (CTRL[1] == 1'b0) begin
					Result8 = IntR8 & ~L[7:0];
					Result16 = IntR16 & ~L;
				end
				else begin
					Result8 = IntR8 | L[7:0];
					Result16 = IntR16 | L;
				end
				temp8 = IntR8 & L[7:0];
				temp16 = IntR16 & L;
				if (((temp8 == 8'h00) & (w16 == 1'b0)) | ((temp16 == 16'h0000) & (w16 == 1'b1)))
					ZR = 1'b1;
			end
			default:
				;
		endcase
	end
	always @(*) begin
		VO = VI;
		if (w16 == 1'b0)
			SO = Result8[7];
		else
			SO = Result16[15];
		case (CTRL[4-:3])
			3'b001:
				if (CTRL[1] == 1'b1) begin
					if (w16 == 1'b0) begin
						VO = IntR8[6];
						SO = IntR8[7];
					end
					else begin
						VO = IntR16[14];
						SO = IntR16[15];
					end
				end
			3'b011: VO = AddVO;
			3'b101: SO = SI;
			3'b111:
				if (CTRL[1] == 1'b1)
					VO = AddVO;
			default:
				;
		endcase
	end
	assign ZO = (CTRL[4-:3] == 3'b101 ? ZR : (((w16 == 1'b0) & (Result8 == 8'h00)) | ((w16 == 1'b1) & (Result16 == 16'h0000)) ? 1'b1 : 1'b0));
	assign RES = (w16 == 1'b0 ? {8'h00, Result8} : Result16);
	assign IntR = (w16 == 1'b0 ? {8'h00, IntR8} : IntR16);
endmodule
module BCDAdder (
	A,
	B,
	CI,
	S,
	CO,
	VO,
	ADD,
	BCD
);
	input [3:0] A;
	input [3:0] B;
	input CI;
	output wire [3:0] S;
	output wire CO;
	output wire VO;
	input ADD;
	input BCD;
	wire [3:0] B2;
	wire [3:0] BIN_S;
	wire BIN_CO;
	wire [3:0] BCD_B;
	wire BCD_CO;
	assign B2 = B ^ {4 {~ADD}};
	adder4 bin_adder(
		.A(A),
		.B(B2),
		.CI(CI),
		.S(BIN_S),
		.CO(BIN_CO)
	);
	assign BCD_CO = (((BIN_S[3] & BIN_S[2]) | (BIN_S[3] & BIN_S[1])) & ADD) | ~(BIN_CO ^ ADD);
	assign BCD_B = {~ADD, (BCD_CO & BCD) ^ ~ADD, (BCD_CO & BCD) ^ ~ADD, ~ADD};
	adder4 bcd_corr_adder(
		.A(BIN_S),
		.B(BCD_B),
		.CI(~ADD),
		.S(S),
		.CO()
	);
	assign CO = (BCD == 1'b0 ? BIN_CO : BCD_CO ^ ~ADD);
	assign VO = ~(A[3] ^ B2[3]) & (A[3] ^ BIN_S[3]);
endmodule
module bit_adder (
	A,
	B,
	CI,
	S,
	CO
);
	input A;
	input B;
	input CI;
	output wire S;
	output wire CO;
	assign S = ((((~A & ~B) & CI) | ((~A & B) & ~CI)) | ((A & ~B) & ~CI)) | ((A & B) & CI);
	assign CO = ((((~A & B) & CI) | ((A & ~B) & CI)) | ((A & B) & ~CI)) | ((A & B) & CI);
endmodule
module P65C816 (
	CLK,
	RST_N,
	CE,
	RDY_IN,
	NMI_N,
	IRQ_N,
	ABORT_N,
	D_IN,
	D_OUT,
	A_OUT,
	WE_N,
	RDY_OUT,
	VPA,
	VDA,
	MLB,
	VPB,
	BRK_OUT,
	DBG_REG,
	DBG_DAT_IN,
	DBG_DAT_OUT,
	DBG_DAT_WR
);
	input CLK;
	input RST_N;
	input CE;
	input RDY_IN;
	input NMI_N;
	input IRQ_N;
	input ABORT_N;
	input [7:0] D_IN;
	output wire [7:0] D_OUT;
	output wire [23:0] A_OUT;
	output reg WE_N;
	output wire RDY_OUT;
	output reg VPA;
	output reg VDA;
	output reg MLB;
	output reg VPB;
	output reg BRK_OUT;
	input [7:0] DBG_REG;
	input [7:0] DBG_DAT_IN;
	output reg [7:0] DBG_DAT_OUT;
	input DBG_DAT_WR;
	reg [15:0] A;
	reg [15:0] X;
	reg [15:0] Y;
	reg [15:0] D;
	reg [15:0] SP;
	reg [15:0] T;
	reg [7:0] PBR;
	reg [7:0] DBR;
	reg [8:0] P;
	wire [15:0] PC;
	reg [7:0] DR;
	wire EF;
	wire XF;
	wire MF;
	reg oldXF;
	wire [15:0] SB;
	wire [15:0] DB;
	wire EN;
	wire [54:0] MC;
	reg [7:0] IR;
	wire [7:0] NextIR;
	reg [3:0] STATE;
	reg [3:0] NextState;
	reg GotInterrupt;
	reg IsResetInterrupt;
	reg IsNMIInterrupt;
	reg IsIRQInterrupt;
	wire IsABORTInterrupt;
	wire IsBRKInterrupt;
	wire IsCOPInterrupt;
	reg JumpTaken;
	wire JumpNoOverflow;
	wire IsBranchCycle1;
	wire w16;
	wire DLNoZero;
	reg WAIExec;
	reg STPExec;
	reg NMI_SYNC;
	reg IRQ_SYNC;
	reg NMI_ACTIVE;
	reg IRQ_ACTIVE;
	reg OLD_NMI_N;
	wire OLD_NMI2_N;
	reg [23:0] ADDR_BUS;
	wire [15:0] AluR;
	wire [15:0] AluIntR;
	wire CO;
	wire VO;
	wire SO;
	wire ZO;
	wire [16:0] AA;
	wire [7:0] AB;
	wire AALCarry;
	wire [15:0] DX;
	reg DBG_DAT_WRr;
	reg [23:0] DBG_BRK_ADDR;
	reg [7:0] DBG_CTRL;
	reg DBG_RUN_LAST;
	wire [15:0] DBG_NEXT_PC;
	reg [23:0] JSR_RET_ADDR;
	reg JSR_FOUND;
	assign EN = ((RDY_IN & CE) & ~WAIExec) & ~STPExec;
	assign IsBranchCycle1 = ((IR[4:0] == 5'b10000) & (STATE == 4'b0001) ? 1'b1 : 1'b0);
	always @(*)
		case (IR[7:5])
			3'b000: JumpTaken = ~P[7];
			3'b001: JumpTaken = P[7];
			3'b010: JumpTaken = ~P[6];
			3'b011: JumpTaken = P[6];
			3'b100: JumpTaken = ~P[0];
			3'b101: JumpTaken = P[0];
			3'b110: JumpTaken = ~P[1];
			3'b111: JumpTaken = P[1];
			default: JumpTaken = 1'b0;
		endcase
	assign DLNoZero = (D[7:0] == 8'h00 ? 1'b0 : 1'b1);
	assign NextIR = (STATE != 4'b0000 ? IR : (GotInterrupt == 1'b1 ? 8'h00 : D_IN));
	always @(*)
		case (MC[46-:3])
			3'b000: NextState = STATE + 4'd1;
			3'b001:
				if ((AALCarry == 1'b0) & ((XF == 1'b1) | (EF == 1'b1)))
					NextState = STATE + 4'd2;
				else
					NextState = STATE + 4'd1;
			3'b010:
				if ((IsBranchCycle1 == 1'b1) & (JumpTaken == 1'b1))
					NextState = 4'b0010;
				else
					NextState = 4'b0000;
			3'b011:
				if ((JumpNoOverflow == 1'b1) | (EF == 1'b0))
					NextState = 4'b0000;
				else
					NextState = STATE + 4'd1;
			3'b100:
				if ((((MC[21] == 1'b0) & (MF == 1'b0)) & (EF == 1'b0)) | (((MC[21] == 1'b1) & (XF == 1'b0)) & (EF == 1'b0)))
					NextState = STATE + 4'd1;
				else
					NextState = 4'b0000;
			3'b101:
				if ((DLNoZero == 1'b1) & (EF == 1'b0))
					NextState = STATE + 4'd1;
				else
					NextState = STATE + 4'd2;
			3'b110:
				if ((((MC[21] == 1'b0) & (MF == 1'b0)) & (EF == 1'b0)) | (((MC[21] == 1'b1) & (XF == 1'b0)) & (EF == 1'b0)))
					NextState = STATE + 4'd1;
				else
					NextState = STATE + 4'd2;
			3'b111:
				if (EF == 1'b0)
					NextState = STATE + 4'd1;
				else if ((EF == 1'b1) & (IR == 8'h40))
					NextState = 4'b0000;
				else
					NextState = STATE + 4'd2;
			default:
				;
		endcase
	wire LAST_CYCLE = (NextState == 4'b0000 ? 1'b1 : 1'b0);
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			STATE <= {4 {1'b0}};
			IR <= {8 {1'b0}};
		end
		else if (EN == 1'b1) begin
			IR <= NextIR;
			STATE <= NextState;
		end
	mcode MCode(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		.IR(NextIR),
		.STATE(NextState),
		.M(MC)
	);
	AddrGen AddrGen(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		.LOAD_PC(MC[28-:3]),
		.PCDec(CO),
		.GotInterrupt(GotInterrupt),
		.ADDR_CTRL(MC[36-:8]),
		.IND_CTRL(MC[38-:2]),
		.D_IN(D_IN),
		.X(X),
		.Y(Y),
		.D(D),
		.S(SP),
		.T(T),
		.DR(DR),
		.DBR(DBR),
		.e6502(EF),
		.PC(PC),
		.AA(AA),
		.AB(AB),
		.DX(DX),
		.AALCarry(AALCarry),
		.JumpNoOfl(JumpNoOverflow)
	);
	assign w16 = (MC[47] == 1'b1 ? 1'b1 : ((IR == 8'heb) | (IR == 8'hab) ? 1'b0 : (((IR == 8'h44) | (IR == 8'h54)) & (STATE == 4'b0101) ? 1'b1 : (((MC[21] == 1'b0) & (MF == 1'b0)) & (EF == 1'b0) ? 1'b1 : (((MC[21] == 1'b1) & (XF == 1'b0)) & (EF == 1'b0) ? 1'b1 : 1'b0)))));
	assign SB = (MC[12:10] == 3'b000 ? A : (MC[12:10] == 3'b001 ? X : (MC[12:10] == 3'b010 ? Y : (MC[12:10] == 3'b011 ? D : (MC[12:10] == 3'b100 ? T : (MC[12:10] == 3'b101 ? SP : (MC[12:10] == 3'b110 ? {8'h00, PBR} : (MC[12:10] == 3'b111 ? {8'h00, DBR} : 16'h0000))))))));
	assign DB = (MC[9:7] == 3'b000 ? {8'h00, D_IN} : (MC[9:7] == 3'b001 ? {D_IN, DR} : (MC[9:7] == 3'b010 ? SB : (MC[9:7] == 3'b011 ? D : (MC[9:7] == 3'b100 ? T : (MC[9:7] == 3'b101 ? 16'h0001 : 16'h0000))))));
	ALU ALU(
		.CTRL(MC[54-:8]),
		.L(SB),
		.R(DB),
		.w16(w16),
		.BCD(P[3]),
		.CI(P[0]),
		.VI(P[6]),
		.SI(P[7]),
		.CO(CO),
		.VO(VO),
		.SO(SO),
		.ZO(ZO),
		.RES(AluR),
		.IntR(AluIntR)
	);
	assign MF = P[5];
	assign XF = P[4];
	assign EF = P[8];
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			A <= {16 {1'b0}};
			X <= {16 {1'b0}};
			Y <= {16 {1'b0}};
			SP <= 16'h0100;
			oldXF <= 1'b1;
		end
		else if (((IR == 8'hfb) & (P[0] == 1'b1)) & (MC[19-:3] == 3'b101)) begin
			X[15:8] <= 8'h00;
			Y[15:8] <= 8'h00;
			SP[15:8] <= 8'h01;
			oldXF <= 1'b1;
		end
		else if (EN == 1'b1) begin
			if (MC[22-:3] == 3'b110) begin
				if (((MC[6] == 1'b1) & (XF == 1'b0)) & (EF == 1'b0)) begin
					X[15:8] <= AluR[15:8];
					X[7:0] <= AluR[7:0];
				end
				else if ((MC[5] == 1'b1) & ((XF == 1'b1) | (EF == 1'b1))) begin
					X[7:0] <= AluR[7:0];
					X[15:8] <= 8'h00;
				end
			end
			if (MC[22-:3] == 3'b101) begin
				if (IR == 8'heb) begin
					A[15:8] <= A[7:0];
					A[7:0] <= A[15:8];
				end
				else if ((((MC[6] == 1'b1) & (MF == 1'b0)) & (EF == 1'b0)) | ((MC[6] == 1'b1) & (w16 == 1'b1))) begin
					A[15:8] <= AluR[15:8];
					A[7:0] <= AluR[7:0];
				end
				else if ((MC[5] == 1'b1) & ((MF == 1'b1) | (EF == 1'b1)))
					A[7:0] <= AluR[7:0];
			end
			if (MC[22-:3] == 3'b111) begin
				if (((MC[6] == 1'b1) & (XF == 1'b0)) & (EF == 1'b0)) begin
					Y[15:8] <= AluR[15:8];
					Y[7:0] <= AluR[7:0];
				end
				else if ((MC[5] == 1'b1) & ((XF == 1'b1) | (EF == 1'b1))) begin
					Y[7:0] <= AluR[7:0];
					Y[15:8] <= 8'h00;
				end
			end
			oldXF <= XF;
			if (((XF == 1'b1) & (oldXF == 1'b0)) & (EF == 1'b0)) begin
				X[15:8] <= 8'h00;
				Y[15:8] <= 8'h00;
			end
			case (MC[25-:3])
				3'b000:
					;
				3'b001:
					if (EF == 1'b0)
						SP <= SP + 16'd1;
					else
						SP[7:0] <= SP[7:0] + 8'd1;
				3'b010:
					if ((MC[6] == 1'b0) & (w16 == 1'b1)) begin
						if (EF == 1'b0)
							SP <= SP + 16'd1;
						else
							SP[7:0] <= SP[7:0] + 8'd1;
					end
				3'b011:
					if (EF == 1'b0)
						SP <= SP - 16'd1;
					else
						SP[7:0] <= SP[7:0] - 8'd1;
				3'b100:
					if (EF == 1'b0)
						SP <= A;
					else
						SP <= {8'h01, A[7:0]};
				3'b101:
					if (EF == 1'b0)
						SP <= X;
					else
						SP <= {8'h01, X[7:0]};
				default:
					;
			endcase
		end
	always @(posedge CLK)
		if (RST_N == 1'b0)
			P <= 9'b100110100;
		else if (EN == 1'b1)
			case (MC[19-:3])
				3'b000: P <= P;
				3'b001:
					if (((((((((MC[21] == 1'b0) & (MC[5] == 1'b1)) & ((MF == 1'b1) | (EF == 1'b1))) | (((MC[21] == 1'b1) & (MC[5] == 1'b1)) & ((XF == 1'b1) | (EF == 1'b1)))) | (((MC[21] == 1'b0) & (MC[6] == 1'b1)) & ((MF == 1'b0) & (EF == 1'b0)))) | (((MC[21] == 1'b1) & (MC[6] == 1'b1)) & ((XF == 1'b0) & (EF == 1'b0)))) | (((MC[21] == 1'b0) & (MC[6] == 1'b1)) & (w16 == 1'b1))) | (IR == 8'heb)) | (IR == 8'hab)) begin
						P[1:0] <= {ZO, CO};
						P[7:6] <= {SO, VO};
					end
				3'b010: begin
					P[2] <= 1'b1;
					P[3] <= 1'b0;
				end
				3'b011: begin
					P[7:6] <= D_IN[7:6];
					P[5] <= D_IN[5] | EF;
					P[4] <= D_IN[4] | EF;
					P[3:0] <= D_IN[3:0];
				end
				3'b100:
					case (IR[7:6])
						2'b00: P[0] <= IR[5];
						2'b01: P[2] <= IR[5];
						2'b10: P[6] <= 1'b0;
						2'b11: P[3] <= IR[5];
						default:
							;
					endcase
				3'b101: begin
					P[8] <= P[0];
					P[0] <= P[8];
					if (P[0] == 1'b1) begin
						P[4] <= 1'b1;
						P[5] <= 1'b1;
					end
				end
				3'b110:
					case (IR[5])
						1'b1: P[7:0] <= P[7:0] | {DR[7:6], DR[5] & ~EF, DR[4] & ~EF, DR[3:0]};
						1'b0: P[7:0] <= P[7:0] & ~{DR[7:6], DR[5] & ~EF, DR[4] & ~EF, DR[3:0]};
						default:
							;
					endcase
				3'b111: P[1] <= ZO;
				default:
					;
			endcase
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			T <= {16 {1'b0}};
			DR <= {8 {1'b0}};
			D <= {16 {1'b0}};
			PBR <= {8 {1'b0}};
			DBR <= {8 {1'b0}};
		end
		else if (EN == 1'b1) begin
			DR <= D_IN;
			case (MC[16-:2])
				2'b01:
					if (MC[6] == 1'b1)
						T[15:8] <= D_IN;
					else
						T[7:0] <= D_IN;
				2'b10: T <= AluR;
				default:
					;
			endcase
			case (MC[14-:2])
				2'b01: D <= AluIntR;
				2'b10:
					if ((IR == 8'h00) | (IR == 8'h02))
						PBR <= {8 {1'b0}};
					else
						PBR <= D_IN;
				2'b11:
					if ((IR == 8'h44) | (IR == 8'h54))
						DBR <= D_IN;
					else
						DBR <= AluIntR[7:0];
				default:
					;
			endcase
		end
	assign D_OUT = ((MC[4-:3] == 3'b010) & (MC[6] == 1'b1) ? PC[15:8] : ((MC[4-:3] == 3'b010) & (MC[6] == 1'b0) ? PC[7:0] : ((MC[4-:3] == 3'b011) & (MC[6] == 1'b1) ? AA[15:8] : ((MC[4-:3] == 3'b011) & (MC[6] == 1'b0) ? AA[7:0] : (MC[4-:3] == 3'b100 ? {P[7], P[6], P[5] | EF, P[4] | (~GotInterrupt & EF), P[3:0]} : ((MC[4-:3] == 3'b101) & (MC[6] == 1'b1) ? SB[15:8] : ((MC[4-:3] == 3'b101) & (MC[6] == 1'b0) ? SB[7:0] : ((MC[4-:3] == 3'b110) & (MC[6] == 1'b1) ? DR : ((MC[4-:3] == 3'b110) & (MC[6] == 1'b0) ? PBR : 8'h00)))))))));
	always @(*) begin
		WE_N = 1'b1;
		if ((MC[4-:3] != 3'b000) & (IsResetInterrupt == 1'b0))
			WE_N = 1'b0;
	end
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			OLD_NMI_N <= 1'b1;
			NMI_SYNC <= 1'b0;
			IRQ_SYNC <= 1'b0;
		end
		else if ((CE == 1'b1) & (IsResetInterrupt == 1'b0)) begin
			OLD_NMI_N <= NMI_N;
			if (((NMI_N == 1'b0) & (OLD_NMI_N == 1'b1)) & (NMI_SYNC == 1'b0))
				NMI_SYNC <= 1'b1;
			else if (((NMI_ACTIVE == 1'b1) & (LAST_CYCLE == 1'b1)) & (EN == 1'b1))
				NMI_SYNC <= 1'b0;
			IRQ_SYNC <= ~IRQ_N;
		end
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			IsResetInterrupt <= 1'b1;
			IsNMIInterrupt <= 1'b0;
			IsIRQInterrupt <= 1'b0;
			GotInterrupt <= 1'b1;
			NMI_ACTIVE <= 1'b0;
			IRQ_ACTIVE <= 1'b0;
		end
		else if ((RDY_IN == 1'b1) & (CE == 1'b1)) begin
			NMI_ACTIVE <= NMI_SYNC;
			IRQ_ACTIVE <= ~IRQ_N;
			if ((LAST_CYCLE == 1'b1) & (EN == 1'b1)) begin
				if (GotInterrupt == 1'b0) begin
					GotInterrupt <= (IRQ_ACTIVE & ~P[2]) | NMI_ACTIVE;
					if (NMI_ACTIVE == 1'b1)
						NMI_ACTIVE <= 1'b0;
				end
				else
					GotInterrupt <= 1'b0;
				IsResetInterrupt <= 1'b0;
				IsNMIInterrupt <= NMI_ACTIVE;
				IsIRQInterrupt <= IRQ_ACTIVE & ~P[2];
			end
		end
	assign IsBRKInterrupt = (IR == 8'h00 ? 1'b1 : 1'b0);
	assign IsCOPInterrupt = (IR == 8'h02 ? 1'b1 : 1'b0);
	assign IsABORTInterrupt = 1'b0;
	always @(posedge CLK)
		if (RST_N == 1'b0) begin
			WAIExec <= 1'b0;
			STPExec <= 1'b0;
		end
		else begin
			if ((EN == 1'b1) & (GotInterrupt == 1'b0)) begin
				if (STATE == 4'b0000) begin
					if (D_IN == 8'hcb)
						WAIExec <= 1'b1;
					else if (D_IN == 8'hdb)
						STPExec <= 1'b1;
				end
			end
			if ((RDY_IN == 1'b1) & (CE == 1'b1)) begin
				if ((((NMI_SYNC == 1'b1) | (IRQ_SYNC == 1'b1)) | (ABORT_N == 1'b0)) & (WAIExec == 1'b1))
					WAIExec <= 1'b0;
			end
		end
	always @(*) begin : xhdl0
		reg [15:0] ADDR_INC;
		ADDR_INC = {14'b00000000000000, MC[40:39]};
		case (MC[43-:3])
			3'b000: ADDR_BUS[23:0] = {PBR, PC};
			3'b001: ADDR_BUS[23:0] = ({DBR, 16'h0000} + {8'h00, AA[15:0]}) + {8'h00, ADDR_INC};
			3'b010:
				if (EF == 1'b0)
					ADDR_BUS[23:0] = {8'h00, SP};
				else
					ADDR_BUS[23:0] = {16'h0001, SP[7:0]};
			3'b011: ADDR_BUS[23:0] = {8'h00, DX + ADDR_INC};
			3'b100: begin
				ADDR_BUS[23:4] = {19'h007ff, EF};
				if (IsResetInterrupt == 1'b1)
					ADDR_BUS[3:0] = {3'b110, MC[39]};
				else if (IsABORTInterrupt == 1'b1)
					ADDR_BUS[3:0] = {3'b100, MC[39]};
				else if (IsNMIInterrupt == 1'b1)
					ADDR_BUS[3:0] = {3'b101, MC[39]};
				else if (IsIRQInterrupt == 1'b1)
					ADDR_BUS[3:0] = {3'b111, MC[39]};
				else if (IsCOPInterrupt == 1'b1)
					ADDR_BUS[3:0] = {3'b010, MC[39]};
				else
					ADDR_BUS[3:0] = {EF, 2'b11, MC[39]};
			end
			3'b101: ADDR_BUS[23:0] = ({AB, 16'h0000} + {7'b0000000, AA}) + {8'h00, ADDR_INC};
			3'b110: ADDR_BUS[23:0] = {8'h00, AA[15:0] + ADDR_INC};
			3'b111: ADDR_BUS[23:0] = {PBR, AA[15:0] + ADDR_INC};
			default:
				;
		endcase
	end
	assign A_OUT = ADDR_BUS;
	always @(*) begin : xhdl1
		reg rmw;
		reg twoCls;
		reg softInt;
		if ((((((((((((((((((((((((((((IR == 8'h06) | (IR == 8'h0e)) | (IR == 8'h16)) | (IR == 8'h1e)) | (IR == 8'hc6)) | (IR == 8'hce)) | (IR == 8'hd6)) | (IR == 8'hde)) | (IR == 8'he6)) | (IR == 8'hee)) | (IR == 8'hf6)) | (IR == 8'hfe)) | (IR == 8'h46)) | (IR == 8'h4e)) | (IR == 8'h56)) | (IR == 8'h5e)) | (IR == 8'h26)) | (IR == 8'h2e)) | (IR == 8'h36)) | (IR == 8'h3e)) | (IR == 8'h66)) | (IR == 8'h6e)) | (IR == 8'h76)) | (IR == 8'h7e)) | (IR == 8'h14)) | (IR == 8'h1c)) | (IR == 8'h04)) | (IR == 8'h0c))
			rmw = 1'b1;
		else
			rmw = 1'b0;
		if (MC[43-:3] == 3'b100)
			VPB = 1'b0;
		else
			VPB = 1'b1;
		if (((MC[43-:3] == 3'b001) | (MC[43-:3] == 3'b011)) & (rmw == 1'b1))
			MLB = 1'b0;
		else
			MLB = 1'b1;
		if (((LAST_CYCLE == 1'b1) & (STATE == 1)) & (MC[1-:2] == 2'b00))
			twoCls = 1'b1;
		else
			twoCls = 1'b0;
		if ((((IsBRKInterrupt == 1'b1) | (IsCOPInterrupt == 1'b1)) & (STATE == 1)) & (GotInterrupt == 1'b0))
			softInt = 1'b1;
		else
			softInt = 1'b0;
		VDA = MC[1];
		VPA = (MC[0] | (twoCls & ((IRQ_ACTIVE & ~P[2]) | NMI_ACTIVE))) | softInt;
	end
	assign RDY_OUT = EN;
	always @(*)
		case (DBG_REG)
			8'h00: DBG_DAT_OUT = A[7:0];
			8'h01: DBG_DAT_OUT = A[15:8];
			8'h02: DBG_DAT_OUT = X[7:0];
			8'h03: DBG_DAT_OUT = X[15:8];
			8'h04: DBG_DAT_OUT = Y[7:0];
			8'h05: DBG_DAT_OUT = Y[15:8];
			8'h06: DBG_DAT_OUT = PC[7:0];
			8'h07: DBG_DAT_OUT = PC[15:8];
			8'h08: DBG_DAT_OUT = P[7:0];
			8'h09: DBG_DAT_OUT = SP[7:0];
			8'h0a: DBG_DAT_OUT = SP[15:8];
			8'h0b: DBG_DAT_OUT = D[7:0];
			8'h0c: DBG_DAT_OUT = D[15:8];
			8'h0d: DBG_DAT_OUT = PBR;
			8'h0e: DBG_DAT_OUT = DBR;
			8'h0f: DBG_DAT_OUT = {6'b000000, MC[40-:2]};
			8'h10: DBG_DAT_OUT = AA[7:0];
			8'h11: DBG_DAT_OUT = AA[15:8];
			8'h12: DBG_DAT_OUT = AB;
			8'h13: DBG_DAT_OUT = DX[7:0];
			8'h14: DBG_DAT_OUT = DX[15:8];
			8'h15: DBG_DAT_OUT = {GotInterrupt, IsResetInterrupt, IsNMIInterrupt, IsIRQInterrupt, RDY_IN, EN, WAIExec, STPExec};
			default: DBG_DAT_OUT = 8'h00;
		endcase
endmodule
module mcode (
	CLK,
	RST_N,
	EN,
	IR,
	STATE,
	M
);
	input CLK;
	input RST_N;
	input EN;
	input [7:0] IR;
	input [3:0] STATE;
	output wire [54:0] M;
	reg [51:0] M_TAB [0:2047];
	initial begin
		M_TAB[0] = 52'b1110000000000000000000000100000000000000000000000001;
		M_TAB[1] = 52'b0000100000000000000000000001100000000000000000111010;
		M_TAB[2] = 52'b0000100000000000000000000001100000000000000001001010;
		M_TAB[3] = 52'b0000100000000000000000000001100000000000000000101010;
		M_TAB[4] = 52'b0000100001000000000000000001100000000000000000110010;
		M_TAB[5] = 52'b0001000000000000000000000000000000000000000000100010;
		M_TAB[6] = 52'b0101000100000000000000001000000010000000000001000010;
		M_TAB[7] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[8] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[9] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[10] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[11] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[12] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[13] = 52'b1000010000100000000000000000010100000000001000100010;
		M_TAB[14] = 52'b0100010100100000000000000000010100000001001001000010;
		M_TAB[15] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[16] = 52'b1110000000000000000000000100000000000000000000000001;
		M_TAB[17] = 52'b0000100000000000000000000001100000000000000000111010;
		M_TAB[18] = 52'b0000100000000000000000000001100000000000000001001010;
		M_TAB[19] = 52'b0000100000000000000000000001100000000000000000101010;
		M_TAB[20] = 52'b0000100001000000000000000001100000000000000000110010;
		M_TAB[21] = 52'b0001000000000000000000000000000000000000000000100010;
		M_TAB[22] = 52'b0101000100000000000000001000000010000000000001000010;
		M_TAB[23] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[24] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[25] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[26] = 52'b1000110000100000000000000000010100000000001000100010;
		M_TAB[27] = 52'b0100110100100000000000000000010100000001001001000010;
		M_TAB[28] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[29] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[30] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[31] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[32] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[33] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[34] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[35] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[36] = 52'b1100110100110000000000000000000000000100011111100000;
		M_TAB[37] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[38] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[39] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[40] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[41] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[42] = 52'b1000110000100000000000000000010100000000001000100010;
		M_TAB[43] = 52'b0100110100100000000000000000010100000001001001000010;
		M_TAB[44] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[45] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[46] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[47] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[48] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[49] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[50] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[51] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[52] = 52'b1100110100110000000000000000000000000100010101100000;
		M_TAB[53] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[54] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[55] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[56] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[57] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[58] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[59] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[60] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[61] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[62] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[63] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[64] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[65] = 52'b0100100000000000000000000001100000000000000000110010;
		M_TAB[66] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[67] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[68] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[69] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[70] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[71] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[72] = 52'b1000000000100000000000000100010100000000001000100001;
		M_TAB[73] = 52'b0100000000100000000000000100010100000001001001000001;
		M_TAB[74] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[75] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[76] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[77] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[78] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[79] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[80] = 52'b0100000000100000000000000000010100000010010101100000;
		M_TAB[81] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[82] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[83] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[84] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[85] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[86] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[87] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[88] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[89] = 52'b0000100000000000000000000001100000011000000001010110;
		M_TAB[90] = 52'b0100100000000000000000000001100000011000000000110110;
		M_TAB[91] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[92] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[93] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[94] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[95] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[96] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[97] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[98] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[99] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[100] = 52'b1100010100110000000000000000000000000100011111100000;
		M_TAB[101] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[102] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[103] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[104] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[105] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[106] = 52'b1000010000100000000000000000010100000000001000100010;
		M_TAB[107] = 52'b0100010100100000000000000000010100000001001001000010;
		M_TAB[108] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[109] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[110] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[111] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[112] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[113] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[114] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[115] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[116] = 52'b1100010100110000000000000000000000000100010101100000;
		M_TAB[117] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[118] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[119] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[120] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[121] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[122] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[123] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[124] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[125] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[126] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[127] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[128] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[129] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[130] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[131] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[132] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[133] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[134] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[135] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[136] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[137] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[138] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[139] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[140] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[141] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[142] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[143] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[144] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[145] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[146] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[147] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[148] = 52'b1000010000100000000000000000010100000000001000100010;
		M_TAB[149] = 52'b0100010100100000000000000000010100000001001001000010;
		M_TAB[150] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[151] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[152] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[153] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[154] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[155] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[156] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[157] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[158] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[159] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[160] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[161] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[162] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[163] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[164] = 52'b1100110100110000000000000000000000000100011101100000;
		M_TAB[165] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[166] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[167] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[168] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[169] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[170] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[171] = 52'b1000110000100000000000000000010100000000001000100010;
		M_TAB[172] = 52'b0100110100100000000000000000010100000001001001000010;
		M_TAB[173] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[174] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[175] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[176] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[177] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[178] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[179] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[180] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[181] = 52'b1100110100110000000000000000000000000100010101100000;
		M_TAB[182] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[183] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[184] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[185] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[186] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[187] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[188] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[189] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[190] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[191] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[192] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[193] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[194] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[195] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[196] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[197] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[198] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[199] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[200] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[201] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[202] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[203] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[204] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[205] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[206] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[207] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[208] = 52'b0100000000100000000000000000010100000010000111100000;
		M_TAB[209] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[210] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[211] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[212] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[213] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[214] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[215] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[216] = 52'b0100000000000000000000000010000000000000000000000000;
		M_TAB[217] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[218] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[219] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[220] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[221] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[222] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[223] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[224] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[225] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[226] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[227] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[228] = 52'b1100010100110000000000000000000000000100011101100000;
		M_TAB[229] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[230] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[231] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[232] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[233] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[234] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[235] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[236] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[237] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[238] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[239] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[240] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[241] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[242] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[243] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[244] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[245] = 52'b1101010100110000000000000000000000000100010101100000;
		M_TAB[246] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[247] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[248] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[249] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[250] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[251] = 52'b1001010000100000000000000000010100000000001000100010;
		M_TAB[252] = 52'b0101010100100000000000000000010100000001001001000010;
		M_TAB[253] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[254] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[255] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[256] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[257] = 52'b0000000000000000000100000000000000000000000000000001;
		M_TAB[258] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[259] = 52'b0000100000000000000000000001100000000000000001001010;
		M_TAB[260] = 52'b0100100000000000000000011001100000000000000000101010;
		M_TAB[261] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[262] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[263] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[264] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[265] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[266] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[267] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[268] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[269] = 52'b1000010000100000000000000000010100000000001010100010;
		M_TAB[270] = 52'b0100010100100000000000000000010100000001001011000010;
		M_TAB[271] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[272] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[273] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[274] = 52'b0000100000000000000000000001100000000000000000011010;
		M_TAB[275] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[276] = 52'b0000000000000000000000000000000010000000000000000001;
		M_TAB[277] = 52'b0000100000000000000000000001100000000000000001001010;
		M_TAB[278] = 52'b0100100000000000000000011001100000000000000000101010;
		M_TAB[279] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[280] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[281] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[282] = 52'b1000110000100000000000000000010100000000001010100010;
		M_TAB[283] = 52'b0100110100100000000000000000010100000001001011000010;
		M_TAB[284] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[285] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[286] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[287] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[288] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[289] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[290] = 52'b1000110000100000000000000000000100000000010010100010;
		M_TAB[291] = 52'b0100110100100000000000000000000100000001010011000010;
		M_TAB[292] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[293] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[294] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[295] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[296] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[297] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[298] = 52'b1000110000100000000000000000010100000000001010100010;
		M_TAB[299] = 52'b0100110100100000000000000000010100000001001011000010;
		M_TAB[300] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[301] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[302] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[303] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[304] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[305] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[306] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[307] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[308] = 52'b1100110100110000000000000000000000000100011001100000;
		M_TAB[309] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[310] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[311] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[312] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[313] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[314] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[315] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[316] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[317] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[318] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[319] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[320] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[321] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[322] = 52'b0100100001100000000000000000000000000000000000000010;
		M_TAB[323] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[324] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[325] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[326] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[327] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[328] = 52'b1000000000100000000000000100010100000000001010100001;
		M_TAB[329] = 52'b0100000000100000000000000100010100000001001011000001;
		M_TAB[330] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[331] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[332] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[333] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[334] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[335] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[336] = 52'b0100000000100000000000000000010100000010011001100000;
		M_TAB[337] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[338] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[339] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[340] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[341] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[342] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[343] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[344] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[345] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[346] = 52'b0000100000000000000000000000100000000000000000100010;
		M_TAB[347] = 52'b0100100000100000000000000000000001000001000011000010;
		M_TAB[348] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[349] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[350] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[351] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[352] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[353] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[354] = 52'b1000010000100000000000000000000100000000010010100010;
		M_TAB[355] = 52'b0100010100100000000000000000000100000001010011000010;
		M_TAB[356] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[357] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[358] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[359] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[360] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[361] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[362] = 52'b1000010000100000000000000000010100000000001010100010;
		M_TAB[363] = 52'b0100010100100000000000000000010100000001001011000010;
		M_TAB[364] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[365] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[366] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[367] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[368] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[369] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[370] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[371] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[372] = 52'b1100010100110000000000000000000000000100011001100000;
		M_TAB[373] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[374] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[375] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[376] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[377] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[378] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[379] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[380] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[381] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[382] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[383] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[384] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[385] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[386] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[387] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[388] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[389] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[390] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[391] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[392] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[393] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[394] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[395] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[396] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[397] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[398] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[399] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[400] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[401] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[402] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[403] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[404] = 52'b1000010000100000000000000000010100000000001010100010;
		M_TAB[405] = 52'b0100010100100000000000000000010100000001001011000010;
		M_TAB[406] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[407] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[408] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[409] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[410] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[411] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[412] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[413] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[414] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[415] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[416] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[417] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[418] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[419] = 52'b1000110000100000000000000000000100000000010010100010;
		M_TAB[420] = 52'b0100110100100000000000000000000100000001010011000010;
		M_TAB[421] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[422] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[423] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[424] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[425] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[426] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[427] = 52'b1000110000100000000000000000010100000000001010100010;
		M_TAB[428] = 52'b0100110100100000000000000000010100000001001011000010;
		M_TAB[429] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[430] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[431] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[432] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[433] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[434] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[435] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[436] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[437] = 52'b1100110100110000000000000000000000000100011001100000;
		M_TAB[438] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[439] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[440] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[441] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[442] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[443] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[444] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[445] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[446] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[447] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[448] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[449] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[450] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[451] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[452] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[453] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[454] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[455] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[456] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[457] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[458] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[459] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[460] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[461] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[462] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[463] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[464] = 52'b0100000000100000000000000000010100000010000101100000;
		M_TAB[465] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[466] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[467] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[468] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[469] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[470] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[471] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[472] = 52'b0100000000100000000000000000010100101010000011100000;
		M_TAB[473] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[474] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[475] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[476] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[477] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[478] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[479] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[480] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[481] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[482] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[483] = 52'b1001010000100000000000000000000100000000010010100010;
		M_TAB[484] = 52'b0101010100100000000000000000000100000001010011000010;
		M_TAB[485] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[486] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[487] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[488] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[489] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[490] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[491] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[492] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[493] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[494] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[495] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[496] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[497] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[498] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[499] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[500] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[501] = 52'b1101010100110000000000000000000000000100011001100000;
		M_TAB[502] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[503] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[504] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[505] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[506] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[507] = 52'b1001010000100000000000000000010100000000001010100010;
		M_TAB[508] = 52'b0101010100100000000000000000010100000001001011000010;
		M_TAB[509] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[510] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[511] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[512] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[513] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[514] = 52'b0000100001100000000000000000100000000000000000000010;
		M_TAB[515] = 52'b0000100000000000000000000000100000000000000000000010;
		M_TAB[516] = 52'b1110100000000000000000001000100000000000000000000010;
		M_TAB[517] = 52'b0100100000000000000000000000000010000000000000000010;
		M_TAB[518] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[519] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[520] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[521] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[522] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[523] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[524] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[525] = 52'b1000010000100000000000000000010100000000001100100010;
		M_TAB[526] = 52'b0100010100100000000000000000010100000001001101000010;
		M_TAB[527] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[528] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[529] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[530] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[531] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[532] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[533] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[534] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[535] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[536] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[537] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[538] = 52'b1000110000100000000000000000010100000000001100100010;
		M_TAB[539] = 52'b0100110100100000000000000000010100000001001101000010;
		M_TAB[540] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[541] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[542] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[543] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[544] = 52'b0000000000000000000000000100000011000000000000000001;
		M_TAB[545] = 52'b0000000000000100000000100100011000001010000101100001;
		M_TAB[546] = 52'b0001010000000110000000000000011100010010000101100010;
		M_TAB[547] = 52'b0000010000000000000000000000000000000000000001011010;
		M_TAB[548] = 52'b0000010000000000000000011100010100000101100001100000;
		M_TAB[549] = 52'b0100010000000000000000000000000000000000000000000000;
		M_TAB[550] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[551] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[552] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[553] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[554] = 52'b1000110000100000000000000000010100000000001100100010;
		M_TAB[555] = 52'b0100110100100000000000000000010100000001001101000010;
		M_TAB[556] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[557] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[558] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[559] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[560] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[561] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[562] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[563] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[564] = 52'b1100110100110000000000000000000000000100010111100000;
		M_TAB[565] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[566] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[567] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[568] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[569] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[570] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[571] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[572] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[573] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[574] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[575] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[576] = 52'b1100000000000000000000000000000100000000000000000000;
		M_TAB[577] = 52'b0000100000000000000000000001100100000000000001010110;
		M_TAB[578] = 52'b0100100000000000000000000001100100000000000000110110;
		M_TAB[579] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[580] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[581] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[582] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[583] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[584] = 52'b1000000000100000000000000100010100000000001100100001;
		M_TAB[585] = 52'b0100000000100000000000000100010100000001001101000001;
		M_TAB[586] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[587] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[588] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[589] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[590] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[591] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[592] = 52'b0100000000100000000000000000010100000010010111100000;
		M_TAB[593] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[594] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[595] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[596] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[597] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[598] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[599] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[600] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[601] = 52'b0100100000000000000000000001100000110000000000110110;
		M_TAB[602] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[603] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[604] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[605] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[606] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[607] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[608] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[609] = 52'b0100000000000000000000001000000000000000000000000001;
		M_TAB[610] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[611] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[612] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[613] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[614] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[615] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[616] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[617] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[618] = 52'b1000010000100000000000000000010100000000001100100010;
		M_TAB[619] = 52'b0100010100100000000000000000010100000001001101000010;
		M_TAB[620] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[621] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[622] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[623] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[624] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[625] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[626] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[627] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[628] = 52'b1100010100110000000000000000000000000100010111100000;
		M_TAB[629] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[630] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[631] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[632] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[633] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[634] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[635] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[636] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[637] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[638] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[639] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[640] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[641] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[642] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[643] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[644] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[645] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[646] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[647] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[648] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[649] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[650] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[651] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[652] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[653] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[654] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[655] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[656] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[657] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[658] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[659] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[660] = 52'b1000010000100000000000000000010100000000001100100010;
		M_TAB[661] = 52'b0100010100100000000000000000010100000001001101000010;
		M_TAB[662] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[663] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[664] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[665] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[666] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[667] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[668] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[669] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[670] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[671] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[672] = 52'b0000000000000000000000000100000011000000000000000001;
		M_TAB[673] = 52'b0000000000000100000000100100011000001010000111100001;
		M_TAB[674] = 52'b0001010000000110000000000000011100010010000111100010;
		M_TAB[675] = 52'b0000010000000000000000000000000000000000000001011010;
		M_TAB[676] = 52'b0000010000000000000000011100010100000101100001100000;
		M_TAB[677] = 52'b0100010000000000000000000000000000000000000000000000;
		M_TAB[678] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[679] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[680] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[681] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[682] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[683] = 52'b1000110000100000000000000000010100000000001100100010;
		M_TAB[684] = 52'b0100110100100000000000000000010100000001001101000010;
		M_TAB[685] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[686] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[687] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[688] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[689] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[690] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[691] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[692] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[693] = 52'b1100110100110000000000000000000000000100010111100000;
		M_TAB[694] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[695] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[696] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[697] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[698] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[699] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[700] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[701] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[702] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[703] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[704] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[705] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[706] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[707] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[708] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[709] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[710] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[711] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[712] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[713] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[714] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[715] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[716] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[717] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[718] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[719] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[720] = 52'b1100000000000000000000000000001100000000000000000000;
		M_TAB[721] = 52'b0000100000000000000000000001101100010000000001010110;
		M_TAB[722] = 52'b0100100000000000000000000001101100010000000000110110;
		M_TAB[723] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[724] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[725] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[726] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[727] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[728] = 52'b0100000000100000000000000000000001000010000010000000;
		M_TAB[729] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[730] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[731] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[732] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[733] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[734] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[735] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[736] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[737] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[738] = 52'b0100000000000000000000011000000010000000000000000001;
		M_TAB[739] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[740] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[741] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[742] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[743] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[744] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[745] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[746] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[747] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[748] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[749] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[750] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[751] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[752] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[753] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[754] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[755] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[756] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[757] = 52'b1101010100110000000000000000000000000100010111100000;
		M_TAB[758] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[759] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[760] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[761] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[762] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[763] = 52'b1001010000100000000000000000010100000000001100100010;
		M_TAB[764] = 52'b0101010100100000000000000000010100000001001101000010;
		M_TAB[765] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[766] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[767] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[768] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[769] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[770] = 52'b0000100000000000000000000000100000000000000000000010;
		M_TAB[771] = 52'b0000100000000000000000001000000000000000000000000010;
		M_TAB[772] = 52'b0100100000000000000000000100000000000000000000000000;
		M_TAB[773] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[774] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[775] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[776] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[777] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[778] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[779] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[780] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[781] = 52'b1000010000100000000000000000010100000000001110100010;
		M_TAB[782] = 52'b0100010100100000000000000000010100000001001111000010;
		M_TAB[783] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[784] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[785] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[786] = 52'b0000000000000000110110000000000000000000000000000000;
		M_TAB[787] = 52'b0000100000000000000000000001100000000000000001001110;
		M_TAB[788] = 52'b0100100000000000000000000001100000000000000000101110;
		M_TAB[789] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[790] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[791] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[792] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[793] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[794] = 52'b1000110000100000000000000000010100000000001110100010;
		M_TAB[795] = 52'b0100110100100000000000000000010100000001001111000010;
		M_TAB[796] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[797] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[798] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[799] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[800] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[801] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[802] = 52'b1000110000000000000000000000000000000000000000111110;
		M_TAB[803] = 52'b0100110100000000000000000000000000000000000001011110;
		M_TAB[804] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[805] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[806] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[807] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[808] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[809] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[810] = 52'b1000110000100000000000000000010100000000001110100010;
		M_TAB[811] = 52'b0100110100100000000000000000010100000001001111000010;
		M_TAB[812] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[813] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[814] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[815] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[816] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[817] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[818] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[819] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[820] = 52'b1100110100110000000000000000000000000100011011100000;
		M_TAB[821] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[822] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[823] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[824] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[825] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[826] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[827] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[828] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[829] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[830] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[831] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[832] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[833] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[834] = 52'b1000100000100000000000000001010100000000000000100010;
		M_TAB[835] = 52'b0100100000100000000000000000010100000001000011000010;
		M_TAB[836] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[837] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[838] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[839] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[840] = 52'b1000000000100000000000000100010100000000001110100001;
		M_TAB[841] = 52'b0100000000100000000000000100010100000001001111000001;
		M_TAB[842] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[843] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[844] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[845] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[846] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[847] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[848] = 52'b0100000000100000000000000000010100000010011011100000;
		M_TAB[849] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[850] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[851] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[852] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[853] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[854] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[855] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[856] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[857] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[858] = 52'b0000100000000000000000000000100000000000000000000010;
		M_TAB[859] = 52'b0000100000000000000000001000100000000000000000000010;
		M_TAB[860] = 52'b0100100000000000000000000100000010000000000000000010;
		M_TAB[861] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[862] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[863] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[864] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[865] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[866] = 52'b0001100000000000000000000000000000000000000000000010;
		M_TAB[867] = 52'b0101100100000000000000001000000000000000000000000010;
		M_TAB[868] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[869] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[870] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[871] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[872] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[873] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[874] = 52'b1000010000100000000000000000010100000000001110100010;
		M_TAB[875] = 52'b0100010100100000000000000000010100000001001111000010;
		M_TAB[876] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[877] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[878] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[879] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[880] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[881] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[882] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[883] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[884] = 52'b1100010100110000000000000000000000000100011011100000;
		M_TAB[885] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[886] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[887] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[888] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[889] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[890] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[891] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[892] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[893] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[894] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[895] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[896] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[897] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[898] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[899] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[900] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[901] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[902] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[903] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[904] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[905] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[906] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[907] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[908] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[909] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[910] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[911] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[912] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[913] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[914] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[915] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[916] = 52'b1000010000100000000000000000010100000000001110100010;
		M_TAB[917] = 52'b0100010100100000000000000000010100000001001111000010;
		M_TAB[918] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[919] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[920] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[921] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[922] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[923] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[924] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[925] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[926] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[927] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[928] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[929] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[930] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[931] = 52'b1000110000000000000000000000000000000000000000111110;
		M_TAB[932] = 52'b0100110100000000000000000000000000000000000001011110;
		M_TAB[933] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[934] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[935] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[936] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[937] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[938] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[939] = 52'b1000110000100000000000000000010100000000001110100010;
		M_TAB[940] = 52'b0100110100100000000000000000010100000001001111000010;
		M_TAB[941] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[942] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[943] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[944] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[945] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[946] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[947] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[948] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[949] = 52'b1100110100110000000000000000000000000100011011100000;
		M_TAB[950] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[951] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[952] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[953] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[954] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[955] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[956] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[957] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[958] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[959] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[960] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[961] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[962] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[963] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[964] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[965] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[966] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[967] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[968] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[969] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[970] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[971] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[972] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[973] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[974] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[975] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[976] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[977] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[978] = 52'b1000100000100000000000000001011100000000000000100010;
		M_TAB[979] = 52'b0100100000100000000000000000011100000001000011000010;
		M_TAB[980] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[981] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[982] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[983] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[984] = 52'b0100000000100000000000000000010100011010000011100000;
		M_TAB[985] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[986] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[987] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[988] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[989] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[990] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[991] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[992] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[993] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[994] = 52'b0000000000000000000010000000000000000000000000000000;
		M_TAB[995] = 52'b0001110000000000000000000000000000000000000000000001;
		M_TAB[996] = 52'b0101110100000000000000001000000000000000000000000001;
		M_TAB[997] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[998] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[999] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1000] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1001] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[1002] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1003] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[1004] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[1005] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1006] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1007] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1008] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1009] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1010] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1011] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[1012] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[1013] = 52'b1101010100110000000000000000000000000100011011100000;
		M_TAB[1014] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[1015] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[1016] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1017] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1018] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[1019] = 52'b1001010000100000000000000000010100000000001110100010;
		M_TAB[1020] = 52'b0101010100100000000000000000010100000001001111000010;
		M_TAB[1021] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1022] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1023] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1024] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[1025] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[1026] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1027] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1028] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1029] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1030] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1031] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1032] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1033] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1034] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1035] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1036] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1037] = 52'b1000010000000000000000000000000000000010000000110110;
		M_TAB[1038] = 52'b0100010100000000000000000000000000000010000001010110;
		M_TAB[1039] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1040] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[1041] = 52'b0000000000000000110110000100000000000000000000000001;
		M_TAB[1042] = 52'b0100000000000000000000001100000000000000000000000000;
		M_TAB[1043] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1044] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1045] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1046] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1047] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1048] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1049] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1050] = 52'b1000110000000000000000000000000100000010000000110110;
		M_TAB[1051] = 52'b0100110100000000000000000000000100000010000001010110;
		M_TAB[1052] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1053] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1054] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1055] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1056] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1057] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1058] = 52'b1000110000000000000000000000001100010010000000110110;
		M_TAB[1059] = 52'b0100110100000000000000000000001100010010000001010110;
		M_TAB[1060] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1061] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1062] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1063] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1064] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1065] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1066] = 52'b1000110000000000000000000000000100000010000000110110;
		M_TAB[1067] = 52'b0100110100000000000000000000000100000010000001010110;
		M_TAB[1068] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1069] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1070] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1071] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1072] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1073] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1074] = 52'b1000110000000000000000000000001000001010000000110110;
		M_TAB[1075] = 52'b0100110100000000000000000000001000001010000001010110;
		M_TAB[1076] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1077] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1078] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1079] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1080] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1081] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1082] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1083] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1084] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[1085] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1086] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1087] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1088] = 52'b0100000000100000000000000000011100010010000101100000;
		M_TAB[1089] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1090] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1091] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1092] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1093] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1094] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1095] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1096] = 52'b1000000011100000000000000100000100000000010010100001;
		M_TAB[1097] = 52'b0100000011100000000000000100000100000001010011000001;
		M_TAB[1098] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1099] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1100] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1101] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1102] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1103] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1104] = 52'b0100000000100000000000000000010100001010000001100000;
		M_TAB[1105] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1106] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1107] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1108] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1109] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1110] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1111] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1112] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[1113] = 52'b0100100000000000000000000001100000111010000000110110;
		M_TAB[1114] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1115] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1116] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1117] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1118] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1119] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1120] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1121] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1122] = 52'b1000010000000000000000000000001100010010000000110110;
		M_TAB[1123] = 52'b0100010100000000000000000000001100010010000001010110;
		M_TAB[1124] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1125] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1126] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1127] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1128] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1129] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1130] = 52'b1000010000000000000000000000000100000010000000110110;
		M_TAB[1131] = 52'b0100010100000000000000000000000100000010000001010110;
		M_TAB[1132] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1133] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1134] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1135] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1136] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1137] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1138] = 52'b1000010000000000000000000000001000001010000000110110;
		M_TAB[1139] = 52'b0100010100000000000000000000001000001010000001010110;
		M_TAB[1140] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1141] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1142] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1143] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1144] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1145] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1146] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[1147] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1148] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1149] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1150] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1151] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1152] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[1153] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[1154] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1155] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1156] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1157] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1158] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1159] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1160] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1161] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1162] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1163] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1164] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1165] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1166] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1167] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1168] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1169] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1170] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1171] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1172] = 52'b1000010000000000000000000000000100000010001000110110;
		M_TAB[1173] = 52'b0100010100000000000000000000000100000010000001010110;
		M_TAB[1174] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1175] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1176] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1177] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1178] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1179] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1180] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1181] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1182] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1183] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1184] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1185] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1186] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1187] = 52'b1000110000000000000000000000001100010010000000110110;
		M_TAB[1188] = 52'b0100110100000000000000000000001100010010000001010110;
		M_TAB[1189] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1190] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1191] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1192] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1193] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1194] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1195] = 52'b1000110000000000000000000000000100000010000000110110;
		M_TAB[1196] = 52'b0100110100000000000000000000000100000010000001010110;
		M_TAB[1197] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1198] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1199] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1200] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1201] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1202] = 52'b0000000000000011001000000000000000000000000000000000;
		M_TAB[1203] = 52'b1000110000000000000000000000001000001010000000110110;
		M_TAB[1204] = 52'b0100110100000000000000000000001000001010000001010110;
		M_TAB[1205] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1206] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1207] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1208] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1209] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1210] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1211] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1212] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[1213] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1214] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1215] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1216] = 52'b0100000000100000000000000000010100010010000001100000;
		M_TAB[1217] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1218] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1219] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1220] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1221] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1222] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1223] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1224] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1225] = 52'b0000000000000010010100000100000000000000000000000001;
		M_TAB[1226] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1227] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1228] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1229] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1230] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1231] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1232] = 52'b0100000000000000000000000010100000000000000000000000;
		M_TAB[1233] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1234] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1235] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1236] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1237] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1238] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1239] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1240] = 52'b0100000000100000000000000000011100001010000001100000;
		M_TAB[1241] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1242] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1243] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1244] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1245] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1246] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1247] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1248] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1249] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1250] = 52'b1000010000000000000000000000000000000000000000111110;
		M_TAB[1251] = 52'b0100010100000000000000000000000000000000000001011110;
		M_TAB[1252] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1253] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1254] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1255] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1256] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1257] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1258] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1259] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1260] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1261] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1262] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1263] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1264] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1265] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1266] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1267] = 52'b1001010000000000000000000000000000000000000000111110;
		M_TAB[1268] = 52'b0101010100000000000000000000000000000000000001011110;
		M_TAB[1269] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1270] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1271] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1272] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1273] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1274] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[1275] = 52'b1001010000000000000000000000000100000010000000110110;
		M_TAB[1276] = 52'b0101010100000000000000000000000100000010000001010110;
		M_TAB[1277] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1278] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1279] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1280] = 52'b1000000000100000000000000100011100000000000000100001;
		M_TAB[1281] = 52'b0100000000100000000000000100011100000001000011000001;
		M_TAB[1282] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1283] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1284] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1285] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1286] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1287] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1288] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1289] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1290] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1291] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1292] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1293] = 52'b1000010000100000000000000000010100000000000000100010;
		M_TAB[1294] = 52'b0100010100100000000000000000010100000001000011000010;
		M_TAB[1295] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1296] = 52'b1000000000100000000000000100011000000000000000100001;
		M_TAB[1297] = 52'b0100000000100000000000000100011000000001000011000001;
		M_TAB[1298] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1299] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1300] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1301] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1302] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1303] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1304] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1305] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1306] = 52'b1000110000100000000000000000010100000000000000100010;
		M_TAB[1307] = 52'b0100110100100000000000000000010100000001000011000010;
		M_TAB[1308] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1309] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1310] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1311] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1312] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1313] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1314] = 52'b1000110000100000000000000000011100000000000000100010;
		M_TAB[1315] = 52'b0100110100100000000000000000011100000001000011000010;
		M_TAB[1316] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1317] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1318] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1319] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1320] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1321] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1322] = 52'b1000110000100000000000000000010100000000000000100010;
		M_TAB[1323] = 52'b0100110100100000000000000000010100000001000011000010;
		M_TAB[1324] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1325] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1326] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1327] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1328] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1329] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1330] = 52'b1000110000100000000000000000011000000000000000100010;
		M_TAB[1331] = 52'b0100110100100000000000000000011000000001000011000010;
		M_TAB[1332] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1333] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1334] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1335] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1336] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1337] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1338] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1339] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1340] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[1341] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1342] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1343] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1344] = 52'b0100000000100000000000000000011100000010000001100000;
		M_TAB[1345] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1346] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1347] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1348] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1349] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1350] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1351] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1352] = 52'b1000000000100000000000000100010100000000000000100001;
		M_TAB[1353] = 52'b0100000000100000000000000100010100000001000011000001;
		M_TAB[1354] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1355] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1356] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1357] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1358] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1359] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1360] = 52'b0100000000100000000000000000011000000010000001100000;
		M_TAB[1361] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1362] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1363] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1364] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1365] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1366] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1367] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1368] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[1369] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[1370] = 52'b0100100000100000000000000000000011000000000000000010;
		M_TAB[1371] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1372] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1373] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1374] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1375] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1376] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1377] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1378] = 52'b1000010000100000000000000000011100000000000000100010;
		M_TAB[1379] = 52'b0100010100100000000000000000011100000001000011000010;
		M_TAB[1380] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1381] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1382] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1383] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1384] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1385] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1386] = 52'b1000010000100000000000000000010100000000000000100010;
		M_TAB[1387] = 52'b0100010100100000000000000000010100000001000011000010;
		M_TAB[1388] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1389] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1390] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1391] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1392] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1393] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1394] = 52'b1000010000100000000000000000011000000000000000100010;
		M_TAB[1395] = 52'b0100010100100000000000000000011000000001000011000010;
		M_TAB[1396] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1397] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1398] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1399] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1400] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1401] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1402] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[1403] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1404] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1405] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1406] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1407] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1408] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[1409] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[1410] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1411] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1412] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1413] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1414] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1415] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1416] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1417] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1418] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1419] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1420] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1421] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1422] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1423] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1424] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1425] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1426] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1427] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1428] = 52'b1000010000100000000000000000010100000000000000100010;
		M_TAB[1429] = 52'b0100010100100000000000000000010100000001000011000010;
		M_TAB[1430] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1431] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1432] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1433] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1434] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1435] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1436] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1437] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1438] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1439] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1440] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1441] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1442] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1443] = 52'b1000110000100000000000000000011100000000000000100010;
		M_TAB[1444] = 52'b0100110100100000000000000000011100000001000011000010;
		M_TAB[1445] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1446] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1447] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1448] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1449] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1450] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1451] = 52'b1000110000100000000000000000010100000000000000100010;
		M_TAB[1452] = 52'b0100110100100000000000000000010100000001000011000010;
		M_TAB[1453] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1454] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1455] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1456] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1457] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1458] = 52'b0000000000000011001000000000000000000000000000000000;
		M_TAB[1459] = 52'b1000110000100000000000000000011000000000000000100010;
		M_TAB[1460] = 52'b0100110100100000000000000000011000000001000011000010;
		M_TAB[1461] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1462] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1463] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1464] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1465] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1466] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1467] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1468] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[1469] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1470] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1471] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1472] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[1473] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1474] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1475] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1476] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1477] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1478] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1479] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1480] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1481] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[1482] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1483] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1484] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1485] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1486] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1487] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1488] = 52'b0100000000100000000000000000011000101010000011100000;
		M_TAB[1489] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1490] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1491] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1492] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1493] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1494] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1495] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1496] = 52'b0100000000100000000000000000011000010010000001100000;
		M_TAB[1497] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1498] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1499] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1500] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1501] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1502] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1503] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1504] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1505] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[1506] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1507] = 52'b1001010000100000000000000000011100000000000000100010;
		M_TAB[1508] = 52'b0101010100100000000000000000011100000001000011000010;
		M_TAB[1509] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1510] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1511] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1512] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1513] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[1514] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1515] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1516] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1517] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1518] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1519] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1520] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1521] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[1522] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1523] = 52'b1001010000100000000000000000011000000000000000100010;
		M_TAB[1524] = 52'b0101010100100000000000000000011000000001000011000010;
		M_TAB[1525] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1526] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1527] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1528] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1529] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1530] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[1531] = 52'b1001010000100000000000000000010100000000000000100010;
		M_TAB[1532] = 52'b0101010100100000000000000000010100000001000011000010;
		M_TAB[1533] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1534] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1535] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1536] = 52'b1000000000100000000000000100001100010000100000100001;
		M_TAB[1537] = 52'b0100000000100000000000000100001100010001100001000001;
		M_TAB[1538] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1539] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1540] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1541] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1542] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1543] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1544] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1545] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1546] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1547] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1548] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1549] = 52'b1000010000100000000000000000000100000000100000100010;
		M_TAB[1550] = 52'b0100010100100000000000000000000100000001100001000010;
		M_TAB[1551] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1552] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[1553] = 52'b0100000011000000000000000000000000000000000000000000;
		M_TAB[1554] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1555] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1556] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1557] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1558] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1559] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1560] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1561] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1562] = 52'b1000110000100000000000000000000100000000100000100010;
		M_TAB[1563] = 52'b0100110100100000000000000000000100000001100001000010;
		M_TAB[1564] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1565] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1566] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1567] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1568] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1569] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1570] = 52'b1000110000100000000000000000001100010000100000100010;
		M_TAB[1571] = 52'b0100110100100000000000000000001100010001100001000010;
		M_TAB[1572] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1573] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1574] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1575] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1576] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1577] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1578] = 52'b1000110000100000000000000000000100000000100000100010;
		M_TAB[1579] = 52'b0100110100100000000000000000000100000001100001000010;
		M_TAB[1580] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1581] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1582] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1583] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1584] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1585] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1586] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[1587] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[1588] = 52'b1100110100110000000000000000000000100010000101100000;
		M_TAB[1589] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[1590] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[1591] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1592] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1593] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1594] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1595] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1596] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[1597] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1598] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1599] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1600] = 52'b0100000000100000000000000000011100010010000111100000;
		M_TAB[1601] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1602] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1603] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1604] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1605] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1606] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1607] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1608] = 52'b1000000000100000000000000100000100000000100000100001;
		M_TAB[1609] = 52'b0100000000100000000000000100000100000001100001000001;
		M_TAB[1610] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1611] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1612] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1613] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1614] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1615] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1616] = 52'b0100000000100000000000000000011000001010000101100000;
		M_TAB[1617] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1618] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1619] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1620] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1621] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1622] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1623] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1624] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[1625] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1626] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1627] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1628] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1629] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1630] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1631] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1632] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1633] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1634] = 52'b1000010000100000000000000000001100010000100000100010;
		M_TAB[1635] = 52'b0100010100100000000000000000001100010001100001000010;
		M_TAB[1636] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1637] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1638] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1639] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1640] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1641] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1642] = 52'b1000010000100000000000000000000100000000100000100010;
		M_TAB[1643] = 52'b0100010100100000000000000000000100000001100001000010;
		M_TAB[1644] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1645] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1646] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1647] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1648] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1649] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1650] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[1651] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[1652] = 52'b1100010100110000000000000000000000100010000101100000;
		M_TAB[1653] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[1654] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[1655] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1656] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1657] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1658] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[1659] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1660] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1661] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1662] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1663] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1664] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[1665] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[1666] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1667] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1668] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1669] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1670] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1671] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1672] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1673] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1674] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1675] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[1676] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1677] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1678] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1679] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1680] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1681] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1682] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1683] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1684] = 52'b1000010000100000000000000000000100000000100000100010;
		M_TAB[1685] = 52'b0100010100100000000000000000000100000001100001000010;
		M_TAB[1686] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1687] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1688] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1689] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1690] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1691] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1692] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1693] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1694] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1695] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1696] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1697] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1698] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1699] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1700] = 52'b0000100000000000000000000001100000000000000001001110;
		M_TAB[1701] = 52'b0100100000000000000000000001100000000000000000101110;
		M_TAB[1702] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1703] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1704] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1705] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1706] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1707] = 52'b1000110000100000000000000000000100000000100000100010;
		M_TAB[1708] = 52'b0100110100100000000000000000000100000001100001000010;
		M_TAB[1709] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1710] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1711] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1712] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1713] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1714] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1715] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[1716] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[1717] = 52'b1100110100110000000000000000000000100010000101100000;
		M_TAB[1718] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[1719] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[1720] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1721] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1722] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1723] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1724] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[1725] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1726] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1727] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1728] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[1729] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1730] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1731] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1732] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1733] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1734] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1735] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1736] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1737] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[1738] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1739] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1740] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1741] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1742] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1743] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1744] = 52'b1100000000000000000000000000001000000000000000000000;
		M_TAB[1745] = 52'b0000100000000000000000000001101000001000000001010110;
		M_TAB[1746] = 52'b0100100000000000000000000001101000001000000000110110;
		M_TAB[1747] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1748] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1749] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1750] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1751] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1752] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[1753] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1754] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1755] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1756] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1757] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1758] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1759] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1760] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1761] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1762] = 52'b0001100000000000000000000000000000000000000000000010;
		M_TAB[1763] = 52'b0001100100000000000000001000000000000000000000000010;
		M_TAB[1764] = 52'b0101101000000000000000000000000010000000000000000010;
		M_TAB[1765] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1766] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1767] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1768] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1769] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[1770] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1771] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1772] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1773] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1774] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1775] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1776] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1777] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1778] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[1779] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[1780] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[1781] = 52'b1101010100110000000000000000000000100010000101100000;
		M_TAB[1782] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[1783] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[1784] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1785] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[1786] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[1787] = 52'b1001010000100000000000000000000100000000100000100010;
		M_TAB[1788] = 52'b0101010100100000000000000000000100000001100001000010;
		M_TAB[1789] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1790] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1791] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1792] = 52'b1000000000100000000000000100001000001000100000100001;
		M_TAB[1793] = 52'b0100000000100000000000000100001000001001100001000001;
		M_TAB[1794] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1795] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1796] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1797] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1798] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1799] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1800] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1801] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1802] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1803] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1804] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1805] = 52'b1000010000100000000000000000010100000000010000100010;
		M_TAB[1806] = 52'b0100010100100000000000000000010100000001010001000010;
		M_TAB[1807] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1808] = 52'b0000000000000000000000000100000000000000000000000001;
		M_TAB[1809] = 52'b0100000011000000000000000000000000000000000000000000;
		M_TAB[1810] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1811] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1812] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1813] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1814] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1815] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1816] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1817] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1818] = 52'b1000110000100000000000000000010100000000010000100010;
		M_TAB[1819] = 52'b0100110100100000000000000000010100000001010001000010;
		M_TAB[1820] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1821] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1822] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1823] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1824] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1825] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1826] = 52'b1000110000100000000000000000001000001000100000100010;
		M_TAB[1827] = 52'b0100110100100000000000000000001000001001100001000010;
		M_TAB[1828] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1829] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1830] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1831] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1832] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1833] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1834] = 52'b1000110000100000000000000000010100000000010000100010;
		M_TAB[1835] = 52'b0100110100100000000000000000010100000001010001000010;
		M_TAB[1836] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1837] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1838] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1839] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1840] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1841] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1842] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[1843] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[1844] = 52'b1100110100110000000000000000000000100010000111100000;
		M_TAB[1845] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[1846] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[1847] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1848] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1849] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1850] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1851] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1852] = 52'b0000111000000000000000100000000000000000000000000010;
		M_TAB[1853] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1854] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1855] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1856] = 52'b0100000000100000000000000000011000001010000111100000;
		M_TAB[1857] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1858] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1859] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1860] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1861] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1862] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1863] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1864] = 52'b1000000000100000000000000100010100000000010000100001;
		M_TAB[1865] = 52'b0100000000100000000000000100010100000001010001000001;
		M_TAB[1866] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1867] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1868] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1869] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1870] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1871] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1872] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1873] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1874] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1875] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1876] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1877] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1878] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1879] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1880] = 52'b0000000000000000000000000000010100000000000001100000;
		M_TAB[1881] = 52'b0100000000100000000000000000000100000010000000100000;
		M_TAB[1882] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1883] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1884] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1885] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1886] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1887] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1888] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1889] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1890] = 52'b1000010000100000000000000000001000001000100000100010;
		M_TAB[1891] = 52'b0100010100100000000000000000001000001001100001000010;
		M_TAB[1892] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1893] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1894] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1895] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1896] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1897] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1898] = 52'b1000010000100000000000000000010100000000010000100010;
		M_TAB[1899] = 52'b0100010100100000000000000000010100000001010001000010;
		M_TAB[1900] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1901] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1902] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1903] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1904] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1905] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1906] = 52'b1100010000001000000000000000000000000000000000100010;
		M_TAB[1907] = 52'b0000010100001000000000000000000000000000000001000010;
		M_TAB[1908] = 52'b1100010100110000000000000000000000100010000111100000;
		M_TAB[1909] = 52'b0000010100000000000000000000000000100000000001010110;
		M_TAB[1910] = 52'b0100010000000000000000000000000000100000000000110110;
		M_TAB[1911] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1912] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1913] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1914] = 52'b0000000000000000000000100100000000000000000000000001;
		M_TAB[1915] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1916] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1917] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1918] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1919] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1920] = 52'b0100000000000000000000000100000000000000000000000001;
		M_TAB[1921] = 52'b0110000000000000000000010000000000000000000000000000;
		M_TAB[1922] = 52'b0100000000000000000000000000000000000000000000000000;
		M_TAB[1923] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1924] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1925] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1926] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1927] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1928] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1929] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1930] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1931] = 52'b0010110100000010010100000000000000000000000000000010;
		M_TAB[1932] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1933] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1934] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1935] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1936] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1937] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1938] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1939] = 52'b0000110100000000000100000000000000000000000000000010;
		M_TAB[1940] = 52'b1000010000100000000000000000010100000000010000100010;
		M_TAB[1941] = 52'b0100010100100000000000000000010100000001010001000010;
		M_TAB[1942] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1943] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1944] = 52'b0000000000000001011011100100000000000000000000000001;
		M_TAB[1945] = 52'b0000000000000000001101100000000000000000000000000000;
		M_TAB[1946] = 52'b0000110000000000100001100000000000000000000000000010;
		M_TAB[1947] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1948] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1949] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1950] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1951] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1952] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[1953] = 52'b0000000000000000000100000100000000000000000000000001;
		M_TAB[1954] = 52'b0000100000000000000000000001100000000000000001001110;
		M_TAB[1955] = 52'b0100100000000000000000000001100000000000000000101110;
		M_TAB[1956] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1957] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1958] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1959] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1960] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1961] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1962] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1963] = 52'b1000110000100000000000000000010100000000010000100010;
		M_TAB[1964] = 52'b0100110100100000000000000000010100000001010001000010;
		M_TAB[1965] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1966] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1967] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1968] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1969] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1970] = 52'b0000000000000001001000000000000000000000000000000000;
		M_TAB[1971] = 52'b1100110000001000000000000000000000000000000000100010;
		M_TAB[1972] = 52'b0000110100001000000000000000000000000000000001000010;
		M_TAB[1973] = 52'b1100110100110000000000000000000000100010000111100000;
		M_TAB[1974] = 52'b0000110100000000000000000000000000100000000001010110;
		M_TAB[1975] = 52'b0100110000000000000000000000000000100000000000110110;
		M_TAB[1976] = 52'b1010000000000001011010000100000000000000000000000001;
		M_TAB[1977] = 52'b0000000000000000001100000000000000000000000000000000;
		M_TAB[1978] = 52'b0000110000000000100000000000000000000000000000000010;
		M_TAB[1979] = 52'b0000110100000010010100000000000000000000000000000010;
		M_TAB[1980] = 52'b0000111000000010000010100000000000000000000000000010;
		M_TAB[1981] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1982] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1983] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1984] = 52'b0100000010000000000000000000000000000000000000000000;
		M_TAB[1985] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1986] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1987] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1988] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1989] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1990] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1991] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1992] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[1993] = 52'b0010000000000010010100000100000000000000000000000001;
		M_TAB[1994] = 52'b0001010000000010000010000000000000000000000000000000;
		M_TAB[1995] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[1996] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[1997] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1998] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[1999] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2000] = 52'b0000000000000000000000000000000000000000000000000000;
		M_TAB[2001] = 52'b0000000000000000000000000000100000000000000000000000;
		M_TAB[2002] = 52'b1000100000100000000000000001011000000000000000100010;
		M_TAB[2003] = 52'b0100100000100000000000000000011000000001000011000010;
		M_TAB[2004] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2005] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2006] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2007] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2008] = 52'b0100000010100000000000000000000000000000000000000000;
		M_TAB[2009] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2010] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2011] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2012] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2013] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2014] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2015] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2016] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[2017] = 52'b0000100000000000000000000001100000000000000001001010;
		M_TAB[2018] = 52'b0000100000000000000000000001100000000000000000101010;
		M_TAB[2019] = 52'b0000000000000000010100000000000000000000000000000001;
		M_TAB[2020] = 52'b0000000000000000000010000000000000000000000000000000;
		M_TAB[2021] = 52'b0001110000000000000000000000000000000000000000000001;
		M_TAB[2022] = 52'b0101110100000000000000001000000000000000000000000001;
		M_TAB[2023] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2024] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[2025] = 52'b0010000000000000010100000100000000000000000000000001;
		M_TAB[2026] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[2027] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[2028] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[2029] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2030] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2031] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2032] = 52'b0000000000000000100001100100000000000000000000000001;
		M_TAB[2033] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[2034] = 52'b0001010000000000000010000000000000000000000000000000;
		M_TAB[2035] = 52'b1101010000001000000000000000000000000000000000100010;
		M_TAB[2036] = 52'b0001010100001000000000000000000000000000000001000010;
		M_TAB[2037] = 52'b1101010100110000000000000000000000100010000111100000;
		M_TAB[2038] = 52'b0001010100000000000000000000000000100000000001010110;
		M_TAB[2039] = 52'b0101010000000000000000000000000000100000000000110110;
		M_TAB[2040] = 52'b0000000000000000100000000100000000000000000000000001;
		M_TAB[2041] = 52'b0000000000000000010100000100000000000000000000000001;
		M_TAB[2042] = 52'b0000000000000000000010100100000000000000000000000001;
		M_TAB[2043] = 52'b1001010000100000000000000000010100000000010000100010;
		M_TAB[2044] = 52'b0101010100100000000000000000010100000001010001000010;
		M_TAB[2045] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2046] = 52'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		M_TAB[2047] = 52'b0000000000000000000000000100000000000000000000000011;
	end
	reg [51:0] MI;
	reg [7:0] ALUFlags;
	always @(*)
		case (MI[11-:5])
			5'd0: ALUFlags = 8'b10010000;
			5'd1: ALUFlags = 8'b10010001;
			5'd2: ALUFlags = 8'b11010000;
			5'd3: ALUFlags = 8'b11110000;
			5'd4: ALUFlags = 8'b10000000;
			5'd5: ALUFlags = 8'b10000100;
			5'd6: ALUFlags = 8'b10001000;
			5'd7: ALUFlags = 8'b10001100;
			5'd8: ALUFlags = 8'b10011110;
			5'd9: ALUFlags = 8'b10000110;
			5'd10: ALUFlags = 8'b00010000;
			5'd11: ALUFlags = 8'b01010000;
			5'd12: ALUFlags = 8'b00110000;
			5'd13: ALUFlags = 8'b01110000;
			5'd14: ALUFlags = 8'b10010100;
			5'd15: ALUFlags = 8'b10010110;
			5'd16: ALUFlags = 8'b10011000;
			default: ALUFlags = 8'b00000000;
		endcase
	always @(posedge CLK or negedge RST_N) begin : sv2v_autoblock_1
		reg [3:0] STATE2;
		if (~RST_N)
			MI <= 52'b0000000000000000000000000100000000000000000000000011;
		else begin
			STATE2 = STATE - 4'd1;
			if (EN == 1'b1)
				MI <= M_TAB[(STATE == 4'b0000 ? 11'd2047 : {IR, STATE2[2:0]})];
		end
	end
	assign M = {ALUFlags, MI[51-:3], MI[48-:3], MI[45-:2], MI[38-:2], MI[36-:8], MI[28-:3], MI[25-:3], MI[22-:3], MI[43-:3], MI[40-:2], MI[19-:2], MI[17-:6], MI[6-:2], MI[4-:3], MI[1-:2]};
endmodule