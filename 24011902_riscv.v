// BLM2022 Odev 3 - Tek Cevrim RISC-V Islemci
// Ogrenci: Omar Nuriyev - 24011902
// Kaynak: Odev2 Soru1 (Q2) - lw,sw,add,sub,slt,or,and,beq,addi,slti,ori,andi,jal,srai

module riscv_core(
    input  wire        clk, reset,
    output wire [31:0] PC,
    input  wire [31:0] Instr,
    output wire        MemWrite,
    output wire [31:0] ALUResult, WriteData,
    input  wire [31:0] ReadData
);
    wire        ALUSrc, RegWrite, Jump, Zero;
    wire [1:0]  ResultSrc, ImmSrc;
    wire [2:0]  ALUControl;
    wire        PCSrc;

    controller c(
        .op(Instr[6:0]),
        .funct3(Instr[14:12]),
        .funct7b5(Instr[30]),
        .Zero(Zero),
        .ResultSrc(ResultSrc),
        .MemWrite(MemWrite),
        .PCSrc(PCSrc),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .Jump(Jump),
        .ImmSrc(ImmSrc),
        .ALUControl(ALUControl)
    );

    datapath dp(
        .clk(clk),
        .reset(reset),
        .ResultSrc(ResultSrc),
        .PCSrc(PCSrc),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .ImmSrc(ImmSrc),
        .ALUControl(ALUControl),
        .Zero(Zero),
        .PC(PC),
        .Instr(Instr),
        .ALUResult(ALUResult),
        .WriteData(WriteData),
        .ReadData(ReadData)
    );
endmodule

module controller(
    input  wire [6:0] op,
    input  wire [2:0] funct3,
    input  wire       funct7b5,
    input  wire       Zero,
    output wire [1:0] ResultSrc,
    output wire       MemWrite,
    output wire       PCSrc, ALUSrc,
    output wire       RegWrite, Jump,
    output wire [1:0] ImmSrc,
    output wire [2:0] ALUControl
);
    wire [1:0] ALUOp;
    wire       Branch;

    maindec md(
        .op(op),
        .ResultSrc(ResultSrc),
        .MemWrite(MemWrite),
        .Branch(Branch),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .Jump(Jump),
        .ImmSrc(ImmSrc),
        .ALUOp(ALUOp)
    );

    aludec ad(
        .opb5(op[5]),
        .funct3(funct3),
        .funct7b5(funct7b5),
        .ALUOp(ALUOp),
        .ALUControl(ALUControl)
    );

    assign PCSrc = (Branch & Zero) | Jump;
endmodule

module maindec(
    input  wire [6:0] op,
    output reg  [1:0] ResultSrc,
    output reg        MemWrite,
    output reg        Branch, ALUSrc,
    output reg        RegWrite, Jump,
    output reg  [1:0] ImmSrc,
    output reg  [1:0] ALUOp
);
    always @(*) begin
        case(op)
            7'b0000011: begin // lw
                RegWrite=1; ImmSrc=2'b00; ALUSrc=1; MemWrite=0;
                ResultSrc=2'b01; Branch=0; ALUOp=2'b00; Jump=0;
            end
            7'b0100011: begin // sw
                RegWrite=0; ImmSrc=2'b01; ALUSrc=1; MemWrite=1;
                ResultSrc=2'b00; Branch=0; ALUOp=2'b00; Jump=0;
            end
            7'b0110011: begin // R-type
                RegWrite=1; ImmSrc=2'bxx; ALUSrc=0; MemWrite=0;
                ResultSrc=2'b00; Branch=0; ALUOp=2'b10; Jump=0;
            end
            7'b1100011: begin // beq
                RegWrite=0; ImmSrc=2'b10; ALUSrc=0; MemWrite=0;
                ResultSrc=2'b00; Branch=1; ALUOp=2'b01; Jump=0;
            end
            7'b0010011: begin // I-type ALU (addi, andi, ori, slti, srai)
                RegWrite=1; ImmSrc=2'b00; ALUSrc=1; MemWrite=0;
                ResultSrc=2'b00; Branch=0; ALUOp=2'b10; Jump=0;
            end
            7'b1101111: begin // jal
                RegWrite=1; ImmSrc=2'b11; ALUSrc=1'bx; MemWrite=0;
                ResultSrc=2'b10; Branch=0; ALUOp=2'bxx; Jump=1;
            end
            default: begin
                RegWrite=0; ImmSrc=2'b00; ALUSrc=0; MemWrite=0;
                ResultSrc=2'b00; Branch=0; ALUOp=2'b00; Jump=0;
            end
        endcase
    end
endmodule

module aludec(
    input  wire       opb5,
    input  wire [2:0] funct3,
    input  wire       funct7b5,
    input  wire [1:0] ALUOp,
    output reg  [2:0] ALUControl
);
    wire rtype_sub = funct7b5 & opb5;

    always @(*) begin
        case(ALUOp)
            2'b00: ALUControl = 3'b000; // add (lw/sw)
            2'b01: ALUControl = 3'b001; // sub (beq)
            2'b10: case(funct3)
                       3'b000: ALUControl = rtype_sub ? 3'b001 : 3'b000; // sub / add, addi
                       3'b010: ALUControl = 3'b101;                        // slt, slti
                       3'b110: ALUControl = 3'b011;                        // or, ori
                       3'b111: ALUControl = 3'b010;                        // and, andi
                       3'b101: ALUControl = funct7b5 ? 3'b100 : 3'bxxx;   // srai
                       default: ALUControl = 3'bxxx;
                   endcase
            default: ALUControl = 3'bxxx;
        endcase
    end
endmodule

module datapath(
    input  wire        clk, reset,
    input  wire [1:0]  ResultSrc,
    input  wire        PCSrc, ALUSrc,
    input  wire        RegWrite,
    input  wire [1:0]  ImmSrc,
    input  wire [2:0]  ALUControl,
    output wire        Zero,
    output wire [31:0] PC,
    input  wire [31:0] Instr,
    output wire [31:0] ALUResult, WriteData,
    input  wire [31:0] ReadData
);
    wire [31:0] PCNext, PCPlus4, PCTarget;
    wire [31:0] ImmExt;
    wire [31:0] SrcA, SrcB;
    wire [31:0] Result;

    flopr #(32) pcreg(clk, reset, PCNext, PC);
    adder       pcadd4(PC, 32'd4, PCPlus4);
    adder       pcaddbranch(PC, ImmExt, PCTarget);
    mux2 #(32)  pcmux(PCPlus4, PCTarget, PCSrc, PCNext);

    regfile     rf(clk, RegWrite, Instr[19:15], Instr[24:20],
                   Instr[11:7], Result, SrcA, WriteData);
    extend      ext(Instr[31:7], ImmSrc, ImmExt);

    mux2 #(32)  srcbmux(WriteData, ImmExt, ALUSrc, SrcB);
    alu         alu_inst(SrcA, SrcB, ALUControl, ALUResult, Zero);

    mux3 #(32)  resmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result);
endmodule

module regfile(
    input  wire        clk,
    input  wire        we3,
    input  wire [ 4:0] a1, a2, a3,
    input  wire [31:0] wd3,
    output wire [31:0] rd1, rd2
);
    reg [31:0] rf[31:0];

    always @(posedge clk)
        if (we3) rf[a3] <= wd3;

    assign rd1 = (a1 != 0) ? rf[a1] : 32'b0;
    assign rd2 = (a2 != 0) ? rf[a2] : 32'b0;
endmodule

module extend(
    input  wire [31:7] instr,
    input  wire [1:0]  immsrc,
    output reg  [31:0] immext
);
    always @(*) begin
        case(immsrc)
            2'b00: immext = {{20{instr[31]}}, instr[31:20]};
            2'b01: immext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            2'b10: immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            2'b11: immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            default: immext = 32'bx;
        endcase
    end
endmodule

module alu(
    input  wire [31:0] a, b,
    input  wire [2:0]  alucontrol,
    output reg  [31:0] result,
    output wire        zero
);
    always @(*) begin
        case(alucontrol)
            3'b000: result = a + b;
            3'b001: result = a - b;
            3'b010: result = a & b;
            3'b011: result = a | b;
            3'b100: result = $signed(a) >>> b[4:0]; // srai
            3'b101: result = ($signed(a) < $signed(b)) ? 32'b1 : 32'b0;
            default: result = 32'bx;
        endcase
    end
    assign zero = (result == 32'b0);
endmodule

module adder(
    input  wire [31:0] a, b,
    output wire [31:0] y
);
    assign y = a + b;
endmodule

module mux2 #(parameter WIDTH = 32) (
    input  wire [WIDTH-1:0] d0, d1,
    input  wire             s,
    output wire [WIDTH-1:0] y
);
    assign y = s ? d1 : d0;
endmodule

module mux3 #(parameter WIDTH = 32) (
    input  wire [WIDTH-1:0] d0, d1, d2,
    input  wire [1:0]       s,
    output wire [WIDTH-1:0] y
);
    assign y = s[1] ? d2 : (s[0] ? d1 : d0);
endmodule

module flopr #(parameter WIDTH = 32) (
    input  wire             clk, reset,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    always @(posedge clk or posedge reset)
        if (reset) q <= 0;
        else       q <= d;
endmodule
