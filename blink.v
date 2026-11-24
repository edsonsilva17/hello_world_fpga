`timescale 1ns/1ps          // mesma unidade de tempo do testbench (só importa na simulação)

module blink #(
    parameter CLK_HZ   = 25_000_000,  // frequência do cristal da placa
    parameter PISCA_HZ = 1            // quantas piscadas completas por segundo
) (
    input  wire clk,    // cristal de 25 MHz da placa
    output wire led_n   // LED da placa, acende em nível baixo
);
    // Uma piscada = meio período aceso + meio período apagado.
    // A 25 MHz e 1 Hz: 25_000_000 / 2 = 12_500_000 ciclos em cada estado.
    localparam LIMITE = CLK_HZ / (2 * PISCA_HZ);

    // $clog2 dá quantos bits cabem 0..LIMITE-1 (12_500_000 → 24 bits)
    reg [$clog2(LIMITE)-1:0] contador = 0;
    reg                      led      = 0;  // 1 = LED aceso

    always @(posedge clk) begin
        if (contador == LIMITE - 1) begin   // chegou ao fim do meio período...
            contador <= 0;                  // ...recomeça a contagem
            led      <= ~led;               // ...e inverte o LED
        end else begin
            contador <= contador + 1;
        end
    end

    assign led_n = ~led;        // placa acende o LED em 0, então inverte
endmodule
