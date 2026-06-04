// BLM2022 Odev 3 - Ust Seviye Modul
// Ogrenci: Omar Nuriyev - 24011902

module top(
    input  wire        clk, reset,
    output wire [31:0] WriteData, DataAdr,
    output wire        MemWrite
);
    wire [31:0] PC, Instr, ReadData;

    riscv_core riscv(
        .clk(clk),
        .reset(reset),
        .PC(PC),
        .Instr(Instr),
        .MemWrite(MemWrite),
        .ALUResult(DataAdr),
        .WriteData(WriteData),
        .ReadData(ReadData)
    );

    imem imem(
        .a(PC),
        .rd(Instr)
    );

    dmem dmem(
        .clk(clk),
        .we(MemWrite),
        .a(DataAdr),
        .wd(WriteData),
        .rd(ReadData)
    );
endmodule
