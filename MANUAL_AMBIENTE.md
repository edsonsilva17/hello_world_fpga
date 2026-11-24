# Manual do ambiente: OSS CAD Suite + Colorlight i9 no Linux

Este manual explica o que instalar e configurar para compilar e gravar projetos na Colorlight i9. Ele foi montado na primeira configuração, em 23/11/2026, no Ubuntu (sessão Wayland). A placa **não conectou de primeira** por falta de permissão USB, e a seção 2 explica a correção.

Faça uma vez por computador. Ao final, o checklist da seção 6 confirma que está tudo certo.

## O que é preciso

| Item | Para quê |
| --- | --- |
| OSS CAD Suite | Todas as ferramentas: simulação, síntese, place & route e gravação |
| Regra udev do gravador | Permitir que seu usuário (e não só o root) fale com a placa pelo USB |
| Grupo `dialout` | Permitir abrir a porta serial da placa (UART) |
| VS Code + extensão Verilog | Editar com destaque de sintaxe e erros na hora (opcional) |

Ferramentas do OSS CAD Suite usadas aqui:

| Ferramenta | Função |
| --- | --- |
| `iverilog` + `vvp` | Compilar e rodar a simulação |
| `gtkwave`, `surfer` | Ver as formas de onda (`.vcd`) |
| `verilator` | Linter (avisos de código) e simulação rápida |
| `yosys` | Síntese: Verilog → peças do ECP5 |
| `nextpnr-ecp5` | Place & route no ECP5 |
| `ecppack` | Gera o bitstream |
| `openFPGALoader`, `ecpdap` | Gravam a placa |
| `cocotb` | Testbenches em Python (fase de verificação) |

## 1. Instalar o OSS CAD Suite

É um pacote único, já compilado, com todas as ferramentas. Ele não precisa de `apt` nem de `sudo`.

1. Baixe o arquivo `oss-cad-suite-linux-x64-AAAAMMDD.tgz` na página de [releases do oss-cad-suite-build](https://github.com/YosysHQ/oss-cad-suite-build/releases). A versão instalada hoje é a `20261103`.
2. Extraia em `~/fpga`:
   ```bash
   mkdir -p ~/fpga
   tar -xzf oss-cad-suite-linux-x64-*.tgz -C ~/fpga
   ```
   O resultado é a pasta `~/fpga/oss-cad-suite`.
3. Coloque as ferramentas no PATH, acrescentando ao fim do `~/.bashrc`:
   ```bash
   export PATH="$HOME/fpga/oss-cad-suite/bin:$PATH"
   ```
   Assim, todo terminal novo encontra `yosys`, `nextpnr-ecp5` etc. A pasta vem **antes** do `$PATH` antigo para ter prioridade sobre versões do sistema.

   A alternativa oficial é `source ~/fpga/oss-cad-suite/environment`. Ela também ajusta Python e bibliotecas, mas muda o prompt e precisa ser rodada em cada terminal.
4. Abra um terminal novo e confira:
   ```bash
   yosys -V
   nextpnr-ecp5 --version
   openFPGALoader -V
   ```
   Cada comando deve mostrar uma versão. Se aparecer `command not found`, o PATH não foi carregado: abra um terminal novo ou rode `source ~/.bashrc`.

**Para atualizar:** baixe uma versão nova, apague a pasta antiga e extraia de novo no mesmo lugar. O PATH continua valendo.

## 2. Conectar a placa (o passo que falhou de primeira)

### Sintoma

O `lsusb` mostrava a placa, mas a gravação falhava:

```
$ openFPGALoader --scan-usb
Error: can't open device with vid:vid = 0x0d28:0x0204. Error code -3 Access denied (insufficient permissions)
```

### Causa

O gravador da placa de extensão é um **DAPLink CMSIS-DAP**, de identificação USB `0d28:0204`. Ele se apresenta ao Linux como um dispositivo HID e aparece como `/dev/hidraw*`. Por padrão, esses arquivos são criados assim:

```
crw------- 1 root root ... /dev/hidraw6
```

Ou seja, só o root lê e escreve. Rodar tudo com `sudo` funcionaria, mas é má prática: o certo é dar permissão ao seu usuário só para esse dispositivo.

### Correção: regra udev

O **udev** é o serviço que cria os arquivos em `/dev` quando um dispositivo é conectado. Uma regra diz a ele quais permissões dar.

1. Confira a identificação da placa (com ela conectada):
   ```bash
   lsusb
   ```
   Procure a linha `0d28:0204`.
2. Crie a regra:
   ```bash
   sudo nano /etc/udev/rules.d/99-cmsis-dap.rules
   ```
   Com este conteúdo:
   ```
   # Gravador CMSIS-DAP da placa de extensão da Colorlight (i5/i9)
   SUBSYSTEM=="usb",  ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0660", GROUP="plugdev", TAG+="uaccess"
   KERNEL=="hidraw*", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0660", GROUP="plugdev", TAG+="uaccess"
   ```
   | Parte | Significado |
   | --- | --- |
   | `99-` no nome | As regras rodam em ordem alfabética; a 99 roda por último e prevalece |
   | `ATTRS{idVendor}`, `ATTRS{idProduct}` | A regra só vale para este dispositivo |
   | Linha `SUBSYSTEM=="usb"` | Acesso USB direto, usado pelo openFPGALoader |
   | Linha `KERNEL=="hidraw*"` | Acesso pelo `/dev/hidraw*`, porque o gravador é HID |
   | `MODE="0660"`, `GROUP="plugdev"` | Dono e grupo `plugdev` leem e escrevem (seu usuário já está no `plugdev`) |
   | `TAG+="uaccess"` | Também dá acesso a quem está logado na tela |
3. Recarregue as regras:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```
4. **Tire e recoloque o cabo USB**, para a regra ser aplicada na conexão.

### Teste

```bash
openFPGALoader --scan-usb
```
Deve listar o gravador, sem erro:
```
Bus device vid:pid       probe_type manufacturer serial    product
001 036    0x0d28:0x0204 cmsisdap   ARM          0700...   DAPLink CMSIS-DAP
```

```bash
openFPGALoader -b colorlight-i5 --detect
```
Lê o chip pelo JTAG:
```
cmsisDAP: failed to find compatible CMSIS-DAP v2 device     ← normal, ver abaixo
cmsisDAP v2: try USB bulk init but failed                  ← normal
HID init successful
index 0:
	idcode 0x41112043
	manufacturer lattice
	family ECP5
	model  LFE5U-45
	irlength 8
```

- **Mensagens de "v2 failed":** o protocolo CMSIS-DAP tem a v1 (HID, mais lenta) e a v2 (USB bulk, mais rápida). Este gravador só fala a v1. O openFPGALoader tenta a v2, não acha e passa para a v1 sozinho. **`HID init successful`** é a linha que importa.
- **`idcode`** é a identificação gravada no silício, mais confiável que a etiqueta. No i9, a blindagem metálica cobre as marcações do chip.
- O perfil `-b colorlight-i5` serve também para o i9: a placa de extensão e o gravador são os mesmos.

## 3. Porta serial (UART)

O mesmo gravador cria uma porta serial, `/dev/ttyACM0`, que vai ser usada nos projetos com UART. Ela pertence ao grupo `dialout`:

```
crw-rw---- 1 root dialout 166, 0 ... /dev/ttyACM0
```

Entre no grupo:

```bash
sudo usermod -aG dialout $USER
```

- **`-aG`** = *append* ao *Group*. Sem o `-a`, você **sairia de todos os outros grupos**, como `sudo` e `docker`.
- O grupo só passa a valer depois de **sair e entrar de novo na sessão** (logout/login). Para testar antes, rode `newgrp dialout` num terminal; o grupo vale só nele.

Confira com:
```bash
id -nG     # a lista deve conter dialout
```

## 4. Identificar a placa e o chip

O i5 e o i9 são módulos muito parecidos, com o mesmo conector, mas o chip e alguns pinos mudam. Confira **sempre** com o `--detect`:

| idcode | Chip | Módulo típico | Opção do nextpnr | LED |
| --- | --- | --- | --- | --- |
| `0x41111043` | LFE5U-25F | Colorlight i5 | `--25k` | `U16` |
| `0x41112043` | LFE5U-45F | **Colorlight i9 (o seu)** | `--45k` | `L2` |

Nos dois módulos, `--package CABGA381 --speed 6` e o clock de 25 MHz no pino `P3` são iguais.

Se o nextpnr gerar para o chip errado, o FPGA recusa o bitstream na gravação, porque o idcode dentro do arquivo não confere.

## 5. VS Code (opcional)

- **Extensão:** *Verilog-HDL/SystemVerilog/Bluespec SystemVerilog*, do autor **mshr-h**. Para instalar: `Ctrl+Shift+X` → buscar "Verilog-HDL".
- **Linter:** em `settings.json`:
  ```json
  "verilog.linting.linter": "verilator"
  ```
  Se aparecer "verilator not found", o VS Code foi aberto pelo menu e não carregou o PATH do `~/.bashrc`. Abra pelo terminal, dentro da pasta do projeto: `code .`
- **Ondas:** a extensão Surfer **não funciona** neste computador (`WebGL isn't supported`), porque o VS Code instalado pelo snap, numa sessão Wayland, não libera a GPU para extensões. Use o Surfer nativo do OSS CAD Suite (`surfer build/blink.vcd`) ou o GTKWave (`gtkwave build/blink.vcd`).

## 6. Checklist

```bash
yosys -V                                   # mostra a versão
openFPGALoader --scan-usb                  # lista 0x0d28:0x0204, sem "Access denied"
openFPGALoader -b colorlight-i5 --detect   # idcode 0x41112043, LFE5U-45
id -nG                                     # contém plugdev e dialout
ls -l /dev/ttyACM0                         # existe com a placa conectada
```

Se tudo isso passar, entre num projeto e rode `./build.sh`.
