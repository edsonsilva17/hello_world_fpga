`timescale 1ns/1ps          // unidade de tempo: #1 = 1 ns

module tb_blink;            // sem portas: o tb é o "mundo" inteiro

    reg  clk = 0;           // reg: o tb dá o valor
    wire led_n;             // wire: quem dá o valor é o circuito testado

    // instancia o circuito (DUT, "device under test") com N=4
    blink #(.N(4)) dut (
        .clk  (clk),
        .led_n(led_n)
    );

    // clock: inverte a cada 20 ns → período de 40 ns = 25 MHz
    always #20 clk = ~clk;

    // mostra no terminal toda vez que o LED muda
    always @(led_n)
        $display("t = %0d ns  led_n = %b", $time, led_n);  // %0d: $time já vem em ns

    initial begin
        $dumpfile("blink.vcd");     // arquivo de formas de onda
        $dumpvars(0, tb_blink);     // grava todos os sinais, em todos os níveis
        #(40*64);                   // espera 64 ciclos de clock
        $finish;                    // encerra; sem isso o clock roda para sempre
    end
endmodule