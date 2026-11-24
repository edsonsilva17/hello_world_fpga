#!/usr/bin/env bash
# build.sh: fluxo completo do projeto blink na Colorlight i9.
#
#   código Verilog ──▶ simulação ──▶ síntese ──▶ place & route ──▶ bitstream ──▶ placa
#                      (iverilog)    (yosys)     (nextpnr-ecp5)    (ecppack)    (openFPGALoader)
#
# Uso:
#   ./build.sh          tudo: simula, compila e grava na SRAM da placa
#   ./build.sh sim      só simula (gera build/blink.vcd)
#   ./build.sh wave     simula e abre as formas de onda no GTKWave
#   ./build.sh build    só compila até o bitstream (build/blink.bit), sem gravar
#   ./build.sh prog     só grava o bitstream que já existe
#   ./build.sh clean    apaga a pasta build/
#
# Todos os arquivos gerados vão para build/ (fora do git).

set -euo pipefail   # para no primeiro erro, em variável não definida ou em falha no meio de um pipe

# ---------------------------------------------------------------------------
# Configuração do projeto: o que muda de um projeto para outro
# ---------------------------------------------------------------------------
TOP=blink                 # nome do módulo de topo (o que tem as portas ligadas aos pinos)
SRC=(blink.v)             # arquivos de hardware: vão para a síntese
TB=tb_blink.v             # testbench: só simulação, nunca vai para a placa
LPF=blink.lpf             # pinos e frequência do clock

# ---------------------------------------------------------------------------
# Configuração da placa: Colorlight i9 = ECP5 LFE5U-45F-6BG381C
# ---------------------------------------------------------------------------
DEVICE=--45k              # tamanho do chip (idcode 0x41112043 lido pelo JTAG)
PACKAGE=CABGA381          # encapsulamento BGA de 381 esferas
SPEED=6                   # grau de velocidade (o "-6" do nome do chip)
BOARD=colorlight-i5       # perfil do openFPGALoader; o gravador é o mesmo do i9

BUILD=build

# Roda sempre a partir da pasta do projeto, de onde quer que o script seja chamado.
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------
etapa() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
erro()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

precisa() {   # confere se as ferramentas estão no PATH antes de começar
    for ferramenta in "$@"; do
        command -v "$ferramenta" >/dev/null \
            || erro "'$ferramenta' não encontrado. Veja MANUAL_AMBIENTE.md (PATH do OSS CAD Suite)."
    done
}

# ---------------------------------------------------------------------------
# Etapas
# ---------------------------------------------------------------------------
simular() {
    precisa iverilog vvp
    mkdir -p "$BUILD"
    etapa "1/4 Simulação (iverilog + vvp)"
    # iverilog compila testbench + circuito num executável de simulação.
    iverilog -Wall -o "$BUILD/sim" "$TB" "${SRC[@]}"
    # vvp roda a simulação. Roda dentro de build/ para o .vcd ser criado lá.
    (cd "$BUILD" && vvp -n sim)
    echo "Formas de onda em $BUILD/$TOP.vcd"
}

sintetizar() {
    precisa yosys
    mkdir -p "$BUILD"
    etapa "2/4 Síntese (yosys): Verilog -> LUTs e flip-flops do ECP5"
    # -q: silencioso na tela; -l: guarda o relatório completo em build/yosys.log
    yosys -q -l "$BUILD/yosys.log" \
          -p "synth_ecp5 -top $TOP -json $BUILD/$TOP.json" \
          "${SRC[@]}"
    echo "Recursos usados (detalhes em $BUILD/yosys.log):"
    # Do resumo final do relatório, mostra só as células por tipo
    # (TRELLIS_FF = flip-flop, LUT4 = lógica, CCU2C = carry de somador, DP16KD = BRAM...).
    sed -n '/=== design hierarchy ===/,$p' "$BUILD/yosys.log" \
        | grep -E '^\s+[0-9]+\s{3}[A-Z]' || true
}

rotear() {
    precisa nextpnr-ecp5
    etapa "3/4 Place & route (nextpnr-ecp5): posiciona no chip e liga aos pinos"
    nextpnr-ecp5 "$DEVICE" --package "$PACKAGE" --speed "$SPEED" \
                 --json "$BUILD/$TOP.json" --lpf "$LPF" \
                 --textcfg "$BUILD/$TOP.config" \
                 -q -l "$BUILD/nextpnr.log"
    echo "Ocupação do chip (detalhes em $BUILD/nextpnr.log):"
    grep -E 'TRELLIS_(IO|FF|COMB):\s+[0-9]+/' "$BUILD/nextpnr.log" | tail -n 3 | sed 's/^Info:\s*/   /'
    echo "Timing (precisa ficar acima da frequência do clock):"
    grep 'Max frequency for clock' "$BUILD/nextpnr.log" | tail -n 1 | sed 's/^Info: */   /'
}

empacotar() {
    precisa ecppack
    etapa "4/4 Bitstream (ecppack)"
    ecppack --compress "$BUILD/$TOP.config" "$BUILD/$TOP.bit"
    echo "Bitstream em $BUILD/$TOP.bit"
}

gravar() {
    precisa openFPGALoader
    [[ -f "$BUILD/$TOP.bit" ]] || erro "$BUILD/$TOP.bit não existe. Rode './build.sh build' antes."
    etapa "Gravando na SRAM do FPGA (openFPGALoader); some ao desligar a placa"
    openFPGALoader -b "$BOARD" "$BUILD/$TOP.bit"
}

compilar() { sintetizar; rotear; empacotar; }

# ---------------------------------------------------------------------------
# Escolha da ação
# ---------------------------------------------------------------------------
case "${1:-tudo}" in
    tudo)  simular; compilar; gravar ;;
    sim)   simular ;;
    wave)  simular; precisa gtkwave; gtkwave "$BUILD/$TOP.vcd" ;;
    build) compilar ;;
    prog)  gravar ;;
    clean) rm -rf "$BUILD"; echo "build/ apagada." ;;
    *)     sed -n '2,15p' "$0"; exit 1 ;;   # mostra o cabeçalho de uso
esac
