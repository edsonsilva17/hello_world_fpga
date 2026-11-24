`timescale 1ns/1ps          // mesma unidade de tempo do testbench (só importa na simulação)

module blink #(parameter N = 25) (
    input  wire clk,    // cristal de 25 MHz da placa
    output wire led_n   // LED da placa, acende em nível baixo
);
    reg [N-1:0] contador = 0;

    always @(posedge clk)          // a cada subida do clock...
        contador <= contador + 1;  // ...soma 1 (<= é atribuição não bloqueante)

    assign led_n = ~contador[N-1]; // o bit mais alto alterna a cada 2^24 ciclos ≈ 0,67 s
endmodule