# fpga-mac

[日本語](README_ja.md)

Build FPGA circuits on an Apple Silicon Mac and run them on a Zynq board, entirely from the
command line.

Vivado runs on x86-64 Linux and Windows, not on macOS. Here it runs in batch mode, with no GUI,
either in Docker under Rosetta 2 on the Mac itself or on an x86-64 Linux machine that the Mac sends
builds to. This repository holds what you need around it:

- `vivado.sh`, which runs Tcl builds and xsim for your project in Docker, locally on Linux, or
  on a Linux build machine over SSH
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

`vivado.sh` runs Vivado in one of three ways, chosen automatically:

| Mode | When | How |
|---|---|---|
| docker | On macOS (default) | In a Docker container under Rosetta 2 |
| local | On x86-64 Linux | Directly |
| remote | When `VIVADO_HOST` is set | Sends the current directory to an x86-64 Linux machine over SSH, runs there, and brings `out/` back |

| Command | What it does |
|---|---|
| `vivado.sh start` | docker: starts container `vivado_<project>` with the project mounted at `/work`. local/remote: checks that Vivado runs |
| `vivado.sh build X.tcl ARGS…` | `vivado -mode batch -source X.tcl -tclargs ARGS…` |
| `vivado.sh sh 'COMMAND'` | Runs a shell command with Vivado's environment (xsim, scripts) |
| `vivado.sh status` | docker: lists running `vivado_*` containers. Otherwise: shows where it runs |
| `vivado.sh stop` | docker: stops this project's container |

The project is the top of the git repository you are in, or the current directory outside git.

- **docker:** commands run in the matching directory inside the container, so relative paths in
  Tcl work when you call it from `hw/`. Each project gets its own container, so several can run at
  once. It needs no VNC and does not interfere with the GUI container from vivado-on-silicon-mac.
- **remote:** the current directory is copied with rsync to
  `~/fpga-work/<project>/<path from the top>/` on the remote machine, without `.git/`, `prj_*/`,
  `.Xil/` and `sim/work/`. Only `out/` comes back. Call it from a directory that holds everything the
  build needs, such as `hw/`.

| Variable | Default | |
|---|---|---|
| `VIVADO_VER` | `2024.1` | |
| `VIVADO_MAC` | `~/tools/vivado-on-silicon-mac-main` | docker: folder holding `Xilinx/Vivado/<version>` |
| `VIVADO_DIR` | `/tools/Xilinx` | local, remote: Xilinx install folder on the Linux machine |
| `VIVADO_HOST` | | remote: `user@host` |
| `VIVADO_SSH_KEY` | | remote: key file, if it is not in `~/.ssh/config` |
| `FPGA_ROOT` | git top or current directory | The project's top folder |

### Building on an x86-64 Linux machine

Vivado runs natively on x86-64 Linux, without Rosetta or Docker. An old Intel Mac mini with Ubuntu
works well as a build machine that the Apple Silicon Mac sends builds to.

1. Install Vivado 2024.1 on it. The Linux files that vivado-on-silicon-mac installed are ordinary
   x86-64 Linux binaries, so you can also copy `Xilinx/Vivado/2024.1` from the Mac (32 GB, about
   10 minutes over gigabit Ethernet). The free edition needs no license file. After copying,
   replace `/home/user/Xilinx` with the new location in `settings64.sh`,
   `.settings64-Vivado.sh` and their `.csh` versions, and remove the lines in `settings64.sh` that
   source DocNav, Model_Composer and Vitis_HLS if you didn't copy them.
2. **On Ubuntu 24.04**, Vivado 2024.1 needs `libtinfo.so.5`, which 24.04 no longer ships. Both
   Vivado itself and xsim stop with `libtinfo.so.5: cannot open shared object file`. Install the
   22.04 packages from Ubuntu's archive:

   ```bash
   cd /tmp && wget http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.3_amd64.deb http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.3_amd64.deb
   sudo apt install /tmp/libtinfo5_6.3-2ubuntu0.3_amd64.deb /tmp/libncursesw5_6.3-2ubuntu0.3_amd64.deb
   ```

3. From the Mac:

   ```bash
   export VIVADO_HOST=builder@192.168.0.50   # your Linux machine
   cd my-circuit/hw
   vivado.sh start                           # prints the Vivado version
   vivado.sh build build.tcl all 100         # → out/ on the Mac
   ```

   Measured with the PYNQ-Z1 template at 100 MHz: a 2018 Mac mini (Core i7-8700B, 32 GB, Ubuntu
   24.04) took 6 min 37 s including the copy there and back. Docker on an M4 Mac took about 9 min.

## Adding a board

1. Create `boards/<board>/` with the board's PS or pin configuration, a deploy/run script, a
   `README.md` and `README_ja.md`, and a `template/` that builds, simulates and runs on it.
2. Test the template from scratch: `new-project.sh`, xsim, `bd`, `all`, then run it on the
   board.
3. Add it to the table above and in [README_ja.md](README_ja.md). Add what you learned to
   [docs/lessons.md](docs/lessons.md) and [docs/lessons_ja.md](docs/lessons_ja.md).

## Repository layout

```
vivado.sh                 Vivado in Docker, on Linux, or on a remote Linux machine
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
