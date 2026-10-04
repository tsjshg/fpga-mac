# fpga-mac

[日本語](README_ja.md)

Build FPGA circuits on an Apple Silicon Mac and run them on a Zynq board, entirely from the
command line.

Vivado only runs on x86 Linux. Here it runs in Docker under Rosetta 2, in batch mode, with no
GUI. This repository holds what you need around it:

- `vivado.sh`, which starts a container for your project and runs Tcl builds and xsim in it
- `new-project.sh`, which starts a project from a board template that already builds,
  simulates and runs
- per-board files: the PS configuration, a deploy/run script, and the template
- [lessons learned](docs/lessons.md): Vivado in Docker, timing, AXI, DMA, PYNQ, and measuring
  without fooling yourself

Supported boards:

| Board | FPGA | Notes |
|---|---|---|
| [PYNQ-Z1](boards/pynq-z1/README.md) | Zynq XC7Z020 | PYNQ v3.1 image, HP0/HP2 to DDR3 (~2.0 GB/s measured) |

The setup came out of [fpga-pynq-z1](https://github.com/tsjshg/fpga-pynq-z1), which runs a
ternary LLM (BitNet b1.58) on hand-written circuits in a PYNQ-Z1.

## How it fits together

```
 Mac                                                      Board (PYNQ-Z1)
 ─────────────────────────────────────────────────        ──────────────────────────
 your project/                                            ~/your-project/
   hw/rtl/*.v ── sim/run.sh ──► xsim         ┐            *.bit + *.hwh
   hw/build.tcl ── bd ──► block design check │ Docker     host/*.py ──► Overlay()
               └── all ──► out/*.bit, *.hwh  ┘ (Vivado)   run.sh (root, login shell)
   host/*.py                                                    ▲
        └──────────── boards/pynq-z1/pynq.sh push / run ────────┘  (ssh, scp)
```

## Requirements

| | |
|---|---|
| Mac | Apple Silicon, macOS 15 tested ([vivado-on-silicon-mac](https://github.com/ichi4096/vivado-on-silicon-mac) does not support most macOS 14 releases) |
| Docker Desktop | Apple Silicon build. Give it about 15 GB of memory: Vivado starts a ~2.8 GB process per IP |
| Disk | About 45 GB for Vivado 2024.1 with Zynq-7000 and Zynq UltraScale+ installed |
| Vivado | 2024.1. The free Standard edition covers the XC7Z020 |

## Setup (once)

### 1. Install Vivado with vivado-on-silicon-mac

Follow [ichi4096/vivado-on-silicon-mac](https://github.com/ichi4096/vivado-on-silicon-mac). It
builds the `x64-linux` Docker image and installs Vivado into its own folder. Put that folder at
`~/tools/vivado-on-silicon-mac-main`, or set `VIVADO_MAC` to wherever you put it.

- Keep the folder on the internal disk. It is bind-mounted into the container, and external
  drives with exFAT and similar file systems lack UNIX permissions.
- Once the install has finished, you can delete the installer and the tool's `work` folder to
  save space.

### 2. Clone this repository

```bash
git clone https://github.com/tsjshg/fpga-mac.git ~/fpga-mac
```

Optionally put it on your `PATH` so that `vivado.sh` and `new-project.sh` work from anywhere.

### 3. Prepare the board

See the board's page, e.g. [PYNQ-Z1](boards/pynq-z1/README.md): SSH key login, a fixed IP
address, and CMA size.

## Start a project

```bash
~/fpga-mac/new-project.sh pynq-z1 ~/my-circuit
cd ~/my-circuit/hw
~/fpga-mac/vivado.sh start                   # container for this project (a few seconds)
~/fpga-mac/vivado.sh sh 'sim/run.sh'         # xsim with stalls and back-pressure → PASS
~/fpga-mac/vivado.sh build build.tcl bd      # block design check (~30 s)
~/fpga-mac/vivado.sh build build.tcl all     # synthesis to bitstream (~10 min)
```

The new project is self-contained. It has its own copy of the board's PS configuration, so it
builds without fpga-mac (anyone with Vivado can run `vivado -mode batch -source build.tcl`).
Changes to fpga-mac do not flow into existing projects.

Then copy it to the board and run it. The board page has the details:

```bash
export PYNQ_HOST=xilinx@192.168.2.99        # your board
~/fpga-mac/boards/pynq-z1/pynq.sh push my-circuit out/cumsum100.bit out/cumsum100.hwh ../host/*
~/fpga-mac/boards/pynq-z1/pynq.sh run my-circuit cumsum.py
```

## `vivado.sh`

| Command | What it does |
|---|---|
| `vivado.sh start` | Starts container `vivado_<project>` with the project mounted at `/work` |
| `vivado.sh build X.tcl ARGS…` | `vivado -mode batch -source X.tcl -tclargs ARGS…` |
| `vivado.sh sh 'COMMAND'` | Runs a shell command with Vivado's environment (xsim, scripts) |
| `vivado.sh status` | Lists running `vivado_*` containers |
| `vivado.sh stop` | Stops this project's container |

The project is the top of the git repository you are in, or the current directory outside git.
Commands run in the matching directory inside the container, so relative paths in Tcl work
when you call it from `hw/`. Each project gets its own container, so several can run at once.
It needs no VNC and does not interfere with the GUI container from vivado-on-silicon-mac.

| Variable | Default | |
|---|---|---|
| `VIVADO_MAC` | `~/tools/vivado-on-silicon-mac-main` | Folder holding `Xilinx/Vivado/<version>` |
| `VIVADO_VER` | `2024.1` | |
| `FPGA_ROOT` | git top or current directory | Folder to mount at `/work` |

## Adding a board

1. Create `boards/<board>/` with the board's PS or pin configuration, a deploy/run script, a
   `README.md` and `README_ja.md`, and a `template/` that builds, simulates and runs on it.
2. Test the template from scratch: `new-project.sh`, xsim, `bd`, `all`, then run it on the
   board.
3. Add it to the table above and in [README_ja.md](README_ja.md). Add what you learned to
   [docs/lessons.md](docs/lessons.md) and [docs/lessons_ja.md](docs/lessons_ja.md).

## Repository layout

```
vivado.sh                 Vivado in Docker: start / build / sh / status / stop
new-project.sh            new project from boards/<board>/template
docs/lessons.md           what went wrong and what to do instead (English)
docs/lessons_ja.md        the same in Japanese
boards/pynq-z1/
  README.md, README_ja.md board setup, deploy, troubleshooting
  ps7.tcl                 Zynq PS7 configuration (from PYNQ's base overlay)
  pynq.sh                 push files to the board / run a script as root
  template/               DMA → your AXI4-Stream core → DMA, with xsim test and board script
```

## License

BSD 3-Clause ([LICENSE](LICENSE)). The PS7 configuration in `boards/pynq-z1/ps7.tcl` comes from
Xilinx/PYNQ, also under the BSD 3-Clause license but with Xilinx's copyright notice. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Vivado itself is AMD's software under AMD's
license and is not part of this repository.
