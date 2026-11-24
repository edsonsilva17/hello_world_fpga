`timescale 1ns/1ps          // unidade de tempo: #1 = 1 ns

module tb_blink;            // sem portas: o tb é o "mundo" inteiro

    reg  clk = 0;           // reg: o tb dá o valor
    wire led_n;             // wire: quem dá o valor é o circuito testado

    // instancia o circuito (DUT, "device under test").
    // CLK_HZ "de mentira" = 16: LIMITE = 16/2 = 8 ciclos por estado,
    // para a simulação ficar curta (o clock real do tb continua 40 ns).
    blink #(
        .CLK_HZ  (16),
        .PISCA_HZ(1)
    ) dut (
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