`timescale 1ns/1ps
// BLM2022 Odev 3 - Testbench
// Ogrenci: Omar Nuriyev - 24011902
//
// Bellek duzeni (dmem):
//   Adres 0x00-0x4C : ARRAY[0..19]
//   Adres 0x50      : MASK = 0x55555555
//   Adres 0x54-0xA0 : COUNT[0..19] (program tarafindan yazilacak)
//
// Cevrim sayisi (tek cevrimli islemci):
//   - Her eleman icin: 109 cevrim (sabit, ic dongu her zaman 16 kez calisir)
//   - 20 eleman toplam: 5 (init) + 20*109 + 1 (son beq) + 1 (halt) = 2187 cevrim

module tb();
    reg         clk;
    reg         reset;
    wire [31:0] WriteData, DataAdr;
    wire        MemWrite;

    integer i, pass_count, cycle_count;

    // Beklenen COUNT degerleri (dogrulama icin)
    reg [31:0] expected_count [0:19];

    top dut(clk, reset, WriteData, DataAdr, MemWrite);

    // VCD dosyasi
    initial begin
        $dumpfile("24011902.vcd");
        $dumpvars(0, tb);
    end

    // Beklenen degerler
    initial begin
        expected_count[0]  = 32'd0;
        expected_count[1]  = 32'd1;
        expected_count[2]  = 32'd0;
        expected_count[3]  = 32'd1;
        expected_count[4]  = 32'd0;
        expected_count[5]  = 32'd7;
        expected_count[6]  = 32'd9;
        expected_count[7]  = 32'd8;
        expected_count[8]  = 32'd8;
        expected_count[9]  = 32'd16;
        expected_count[10] = 32'd16;
        expected_count[11] = 32'd15;
        expected_count[12] = 32'd9;
        expected_count[13] = 32'd10;
        expected_count[14] = 32'd7;
        expected_count[15] = 32'd8;
        expected_count[16] = 32'd7;
        expected_count[17] = 32'd8;
        expected_count[18] = 32'd10;
        expected_count[19] = 32'd2;
    end

    // dmem'i ARRAY ve MASK ile ilklendir
    initial begin
        // ARRAY[0..19]
        dut.dmem.RAM[0]  = 32'h00000000;
        dut.dmem.RAM[1]  = 32'h00000001;
        dut.dmem.RAM[2]  = 32'h00000200;
        dut.dmem.RAM[3]  = 32'h00400000;
        dut.dmem.RAM[4]  = 32'h80000000;
        dut.dmem.RAM[5]  = 32'h51C06460;
        dut.dmem.RAM[6]  = 32'hDEC287D9;
        dut.dmem.RAM[7]  = 32'h6C896594;
        dut.dmem.RAM[8]  = 32'h99999999;
        dut.dmem.RAM[9]  = 32'hFFFFFFFF;
        dut.dmem.RAM[10] = 32'h7FFFFFFF;
        dut.dmem.RAM[11] = 32'hFFFFFFFE;
        dut.dmem.RAM[12] = 32'hC7B52169;
        dut.dmem.RAM[13] = 32'h8CEFF731;
        dut.dmem.RAM[14] = 32'hA550921E;
        dut.dmem.RAM[15] = 32'h0DB01F33;
        dut.dmem.RAM[16] = 32'h24BB7B48;
        dut.dmem.RAM[17] = 32'h98513914;
        dut.dmem.RAM[18] = 32'hCD76ED30;
        dut.dmem.RAM[19] = 32'hC0000003;
        // MASK = 0x55555555 (adres 0x50 = word 20)
        dut.dmem.RAM[20] = 32'h55555555;
        // COUNT alani sifirla (word 21-40)
        for (i = 21; i <= 40; i = i + 1)
            dut.dmem.RAM[i] = 32'h00000000;
    end

    // Reset ve zaman asimi
    initial begin
        pass_count  = 0;
        cycle_count = 0;
        reset = 1; clk = 0;
        #22; reset = 0;
        // Maksimum 25000 ns (2500 cevrim @ 10ns) bekle
        #25000;
        $display("ZAMAN ASIMI: Simülasyon tamamlanamadi.");
        $finish;
    end

    // 100 MHz saat (10 ns periyot)
    always #5 clk = ~clk;

    // Cevrim sayaci
    always @(posedge clk)
        if (!reset) cycle_count = cycle_count + 1;

    // SW yazma gozlemcisi
    always @(negedge clk) begin
        if (MemWrite) begin
            // COUNT dizisi: adres 0x54-0xA0 (84-160)
            if (DataAdr >= 32'd84 && DataAdr <= 32'd160) begin
                i = (DataAdr - 32'd84) >> 2;
                if (WriteData === expected_count[i])
                    $display("COUNT[%0d] = %0d  DOGRU  (adres=0x%0h, cevrim=%0d)",
                             i, WriteData, DataAdr, cycle_count);
                else
                    $display("COUNT[%0d] = %0d  YANLIS! (beklenen=%0d, adres=0x%0h)",
                             i, WriteData, expected_count[i], DataAdr);
                pass_count = pass_count + 1;
                if (pass_count == 20) begin
                    #20;
                    $display("");
                    $display("=== SONUCLAR ===");
                    $display("Tüm 20 COUNT degeri hesaplandi.");
                    $display("Toplam cevrim sayisi (son COUNT yazimina kadar): %0d", cycle_count);
                    $display("Her eleman icin cevrim sayisi: 109 (sabit, ic dongu her zaman 16 kez)");
                    $display("");
                    $display("Sira  ARRAY       COUNT  Durum");
                    for (i = 0; i < 20; i = i + 1)
                        $display("%2d    0x%08h  %2d     %s",
                                 i+1,
                                 dut.dmem.RAM[i],
                                 dut.dmem.RAM[21+i],
                                 (dut.dmem.RAM[21+i] === expected_count[i]) ? "PASS" : "FAIL");
                    $finish;
                end
            end
        end
    end

endmodule
