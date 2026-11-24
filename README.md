# blink: hello world na Colorlight i9

Um LED que pisca a 1 Hz exato (0,5 s aceso, 0,5 s apagado). É o menor projeto que passa pelo fluxo inteiro de FPGA: escrever o hardware, simular, sintetizar, posicionar e rotear, gerar o bitstream e gravar na placa.

- **Placa:** Colorlight i9 com a placa de extensão (gravador DAPLink CMSIS-DAP).
- **FPGA:** Lattice ECP5 **LFE5U-45F-6BG381C** (idcode `0x41112043`).
- **Ferramentas:** OSS CAD Suite. Para instalar e conectar a placa, veja [MANUAL_AMBIENTE.md](MANUAL_AMBIENTE.md).

## Uso rápido

```bash
./build.sh          # simula, compila e grava na placa: rode isto depois de cada modificação
./build.sh sim      # só simula
./build.sh wave     # simula e abre as ondas no GTKWave
./build.sh build    # compila até o bitstream, sem gravar
./build.sh prog     # grava o último bitstream
./build.sh clean    # apaga build/
```

O script para no primeiro erro. Tudo o que ele gera vai para `build/`, que fica fora do git.

## Arquivos

Você escreve quatro arquivos. As ferramentas geram o resto.

| Arquivo | O que é | Quem lê |
| --- | --- | --- |
| `blink.v` | O circuito, em Verilog | iverilog (simulação) e yosys (síntese) |
| `tb_blink.v` | Testbench: a "placa de mentira" que testa o circuito no computador | Só o iverilog; nunca vai para o FPGA |
| `blink.lpf` | Restrições: em qual pino físico cada sinal sai e qual é a frequência do clock | nextpnr-ecp5 |
| `build.sh` | Roda todas as etapas em ordem | Você |
| `build/sim` | Executável da simulação | vvp |
| `build/blink.vcd` | Formas de onda gravadas na simulação | GTKWave ou Surfer |
| `build/blink.json` | Netlist: o circuito convertido em peças do ECP5 (LUTs, flip-flops, carry) | nextpnr-ecp5 |
| `build/yosys.log` | Relatório da síntese, com a contagem de peças | Você |
| `build/blink.config` | O chip configurado: cada peça posicionada e cada fio roteado, em texto | ecppack |
| `build/nextpnr.log` | Relatório do place & route: ocupação e timing | Você |
| `build/blink.bit` | Bitstream: o arquivo binário que programa o FPGA | openFPGALoader |

## O fluxo

```
SIMULAÇÃO (no computador)
  tb_blink.v ─┐
              ├─▶ [iverilog + vvp] ──▶ blink.vcd ──▶ [GTKWave]
  blink.v ────┘

IMPLEMENTAÇÃO (na placa)
  blink.v ──▶ [yosys] ──▶ blink.json ──▶ [nextpnr-ecp5] ──▶ blink.config ──▶ [ecppack] ──▶ blink.bit ──▶ [openFPGALoader] ──▶ placa
                                                ▲
                                            blink.lpf
```

A simulação e a síntese são caminhos separados. A simulação confere se a **lógica** está certa, de forma rápida e com acesso a qualquer sinal interno. A síntese transforma a lógica em **hardware real**. Erros de lógica são muito mais fáceis de achar na simulação do que na placa.

## Passo a passo: o que o script faz

Estes são os comandos que o `build.sh` roda. Vale rodá-los à mão algumas vezes para entender cada um.

### 1. Simular

```bash
iverilog -Wall -o build/sim tb_blink.v blink.v
cd build && vvp -n sim
```

- **`iverilog`** compila o testbench e o circuito num executável. `-Wall` liga todos os avisos e `-o` dá o nome da saída.
- **`vvp`** executa a simulação. Os `$display` aparecem no terminal, e o `$dumpfile` cria o `blink.vcd`.
- **O que conferir:** `led_n` alterna a cada 320 ns (t = 0, 300, 620, 940…). Com `CLK_HZ = 16` no testbench, `LIMITE = 8`: o LED inverte a cada 8 ciclos de 40 ns.

### 2. Sintetizar

```bash
yosys -p "synth_ecp5 -top blink -json build/blink.json" blink.v
```

- **`yosys`** lê o Verilog e o transforma em peças que existem dentro do ECP5.
- **`synth_ecp5`** é a receita de síntese para essa família de chips. **`-top blink`** diz qual módulo é o de cima, e **`-json`** diz onde salvar a netlist.
- **O que conferir** no resumo final ("Printing statistics"):
  - `25 TRELLIS_FF`: 24 flip-flops do contador, um por bit, mais 1 do registrador `led`.
  - `12 CCU2C`: a cadeia de carry do somador `+1`; cada CCU2C soma 2 bits.
  - `11 LUT4` e `2 PFUMX`: a comparação `contador == LIMITE - 1`, o zerar do contador e o NOT do LED.

  Se aparecerem muito mais ou muito menos peças do que você esperava, algo no Verilog não está descrevendo o que você pensou.

### 3. Posicionar e rotear (place & route)

```bash
nextpnr-ecp5 --45k --package CABGA381 --speed 6 \
             --json build/blink.json --lpf blink.lpf --textcfg build/blink.config
```

- **`nextpnr-ecp5`** decide **onde** cada peça fica dentro do chip (*place*) e **por quais fios** elas se ligam (*route*).
- **`--45k --package CABGA381 --speed 6`** descreve o chip exato: LFE5U-**45**F-**6**BG**381**C. Se o chip estiver errado, a gravação falha por idcode.
- **`--lpf`** traz os pinos e o clock. **`--textcfg`** é o arquivo de saída.
- **O que conferir:**
  - `TRELLIS_FF: 25/43848 0%`: quanto do chip foi usado.
  - `Max frequency for clock ...: 242.07 MHz (PASS at 25.00 MHz)`: o caminho mais lento entre dois flip-flops aguenta 242 MHz. O clock é de 25 MHz, então sobra muita margem. Se aparecer `FAIL`, o circuito pode se comportar errado na placa.

### 4. Gerar o bitstream

```bash
ecppack --compress build/blink.config build/blink.bit
```

- **`ecppack`** converte a configuração em texto no binário que o FPGA entende. **`--compress`** deixa o arquivo menor e a gravação mais rápida.

### 5. Gravar

```bash
openFPGALoader -b colorlight-i5 build/blink.bit
```

- **`-b colorlight-i5`** escolhe o perfil da placa: qual gravador usar (CMSIS-DAP) e como. O i5 e o i9 usam a mesma placa de extensão, então o perfil serve para os dois.
- **Sem `-f`**, a gravação vai para a **SRAM**: é rápida, mas some ao desligar a placa. É o que se usa no dia a dia. Com `-f`, iria para a flash e ficaria permanente.
- As mensagens `failed to find compatible CMSIS-DAP v2 device` são normais: o gravador só fala a v1 (HID), e o openFPGALoader usa a v1 sozinho.

## O que tem dentro de cada arquivo

### `blink.v`: o circuito

Verilog **descreve hardware**. Ele não é executado linha a linha: cada trecho vira um pedaço de circuito, e todos funcionam ao mesmo tempo.

```verilog
module blink #(
    parameter CLK_HZ   = 25_000_000,  // constantes configuráveis na instância
    parameter PISCA_HZ = 1
) (
    input  wire clk,                  // clock de 25 MHz
    output wire led_n                 // LED, aceso em nível baixo (_n = ativo em 0)
);
    localparam LIMITE = CLK_HZ / (2 * PISCA_HZ);   // calculado; não pode ser trocado de fora

    reg [$clog2(LIMITE)-1:0] contador = 0;  // bits suficientes para 0..LIMITE-1
    reg                      led      = 0;  // o "= 0" é carregado pelo bitstream ao ligar

    always @(posedge clk) begin             // a cada subida do clock: vira flip-flops
        if (contador == LIMITE - 1) begin   // fim do meio período
            contador <= 0;
            led      <= ~led;               // inverte o LED
        end else begin
            contador <= contador + 1;       // "<=" atualiza todos os flip-flops juntos
        end
    end

    assign led_n = ~led;                    // lógica combinacional: o LED, invertido
endmodule
```

O hardware que sai disso:

```
              ┌──────────────────────────────────────┐
              │ D                                    │
          ┌───┴──────────┐  Q (24 bits)              │
 clk ───▶ │ 24 flip-flops├──┬──▶ [ +1 ] ──▶ [ MUX ] ─┘
          └──────────────┘  │                  ▲ escolhe 0 quando "fim"
                            ▼                  │
                     [ == LIMITE-1 ? ] ── fim ─┴──▶ inverte ──▶ [ FF led ] ──▶ [NOT] ──▶ pino L2 (LED)
```

- `LIMITE = 25.000.000 / 2 = 12.500.000` ciclos em cada estado. A 40 ns por ciclo, são 0,5 s exatos aceso e 0,5 s apagado: 1 Hz.
- Para outra frequência, troque só `PISCA_HZ`. Ela é exata quando `CLK_HZ / (2 × PISCA_HZ)` dá um número inteiro.
- Com `begin ... end`, o `always` pode ter vários comandos. A indentação é só visual: sem `begin/end`, apenas o primeiro comando ficaria dentro do `always`.
- **`reg`** não quer dizer automaticamente registrador. Ele vira flip-flop porque é atualizado dentro de `always @(posedge clk)`.
- **Regra:** em `always @(posedge clk)`, use `<=`.
- O `= 0` só funciona em FPGA. Num chip ASIC, seria preciso um sinal de reset.
- O `` `timescale `` da primeira linha só vale para a simulação. Ele existe para o circuito e o testbench usarem a mesma unidade de tempo, e a síntese o ignora.

### `blink.lpf`: os pinos

```
LOCATE COMP "clk" SITE "P3";            # sinal clk  → esfera P3 (onde chega o oscilador de 25 MHz)
IOBUF  PORT "clk" IO_TYPE=LVCMOS33;     # padrão elétrico: CMOS 3,3 V
FREQUENCY PORT "clk" 25 MHZ;            # informa a frequência para o nextpnr checar o timing (não gera clock!)
LOCATE COMP "led_n" SITE "L2";          # sinal led_n → esfera L2 (LED do módulo i9)
IOBUF  PORT "led_n" IO_TYPE=LVCMOS33;
```

- Os nomes entre aspas precisam ser **idênticos** aos das portas no Verilog.
- `P3`, `L2` etc. são as coordenadas das esferas do encapsulamento BGA: linha (letra) e coluna (número). Quem decide qual esfera vai para o LED é o desenho da placa, por isso o pino muda entre o i5 (`U16`) e o i9 (`L2`).
- Sem `LOCATE`, o nextpnr escolhe um pino qualquer: o circuito funciona por dentro, mas não está ligado ao LED.

### `tb_blink.v`: o testbench

```verilog
`timescale 1ns/1ps                 // #1 = 1 ns
module tb_blink;                   // sem portas: é o nível mais alto da simulação
    reg  clk = 0;                  // reg: o testbench dá o valor. Sem "= 0", começa em x e nunca oscila
    wire led_n;                    // wire: quem dá o valor é o circuito

    blink #(                       // instância do circuito: .PARAMETRO(valor)
        .CLK_HZ  (16),             // clock "de mentira" para a conta: LIMITE = 8
        .PISCA_HZ(1)
    ) dut (
        .clk  (clk),               // .porta_do_modulo(sinal_do_testbench)
        .led_n(led_n)
    );

    always #20 clk = ~clk;         // 20 ns em 0 e 20 ns em 1 = período de 40 ns = 25 MHz

    always @(led_n)                // sempre que o LED mudar, imprime
        $display("t = %0d ns  led_n = %b", $time, led_n);

    initial begin                  // roda uma vez, no início
        $dumpfile("blink.vcd");    // arquivo de ondas
        $dumpvars(0, tb_blink);    // grava todos os sinais, em todos os níveis
        #(40*64);                  // espera 64 ciclos
        $finish;                   // encerra; sem isso, o clock rodaria para sempre
    end
endmodule
```

- Atrasos (`#20`) e funções com `$` só existem no simulador e não viram hardware.
- **Por que `CLK_HZ = 16`?** Com o valor real, o LED só mudaria depois de 12,5 milhões de ciclos, e a simulação ficaria lenta e com um arquivo enorme. A lógica é a mesma; só a escala muda. É para isso que existe o `parameter`. O clock do testbench continua com 40 ns: o `CLK_HZ` só entra na conta do `LIMITE`.
- **Por que `40*64`?** 40 ns por ciclo × 64 ciclos. Cada piscada leva 16 ciclos, então dá para ver 4 piscadas.
- **`%0d` e não `%0t`:** o `%t` imprime o tempo na precisão do `timescale` (ps) e mostraria "300000". Já o `$time` devolve o valor na unidade do módulo (ns), então `%0d` mostra "300".

## Pinos da Colorlight i9 usados até agora

| Sinal | Pino | Observação |
| --- | --- | --- |
| Clock 25 MHz | `P3` | Igual no i5 |
| LED do módulo | `L2` | Ativo em nível baixo; no i5 é `U16` |

Os pinos da UART do i9 ainda não foram conferidos. Eles são diferentes dos do i5.

## Problemas que já aconteceram

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `Access denied (insufficient permissions)` ao gravar | Faltava a regra udev para o gravador | [MANUAL_AMBIENTE.md](MANUAL_AMBIENTE.md), seção 2 |
| O chip lido é `LFE5U-45`, não 25F | O módulo é um i9, não um i5 | `--45k` no nextpnr e LED no pino `L2` |
| `warning: timescale for blink inherited from another file` | Só o testbench tinha `` `timescale `` | Adicionar a mesma linha ao `blink.v` |
| Tempo impresso 1000 vezes maior | `%0t` imprime em ps | Usar `%0d` com `$time` |
| Surfer no VS Code: `WebGL isn't supported` | VS Code em snap + Wayland não libera a GPU | Usar `surfer build/blink.vcd` ou GTKWave |

## Próximos desafios

1. Fazer o LED piscar a 2 Hz mudando só `PISCA_HZ`: prever na simulação os novos tempos de troca antes de gravar.
2. LED "respirando" com PWM.
3. Testbench que confere sozinho o número de ciclos entre as trocas e acusa erro.
