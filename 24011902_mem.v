// BLM2022 Odev 3 - Bellek Modulleri
// Ogrenci: Omar Nuriyev - 24011902

// Komut bellegi (imem) - imem.mem dosyasindan yuklenir
module imem(
    input  wire [31:0] a,
    output wire [31:0] rd
);
    reg [31:0] RAM[63:0];

    initial begin
        $readmemh("imem.mem", RAM);
    end

    assign rd = RAM[a[31:2]];
endmodule

// Veri bellegi (dmem) - testbench tarafindan ilk degerler atanir
module dmem(
    input  wire        clk, we,
    input  wire [31:0] a, wd,
    output wire [31:0] rd
);
    reg [31:0] RAM[63:0];

    assign rd = RAM[a[31:2]];

    always @(posedge clk)
        if (we) RAM[a[31:2]] <= wd;
endmodule
