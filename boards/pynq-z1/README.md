# PYNQ-Z1

[日本語](README_ja.md) · [back to fpga-mac](../../README.md)

| | |
|---|---|
| FPGA | Zynq XC7Z020 (`xc7z020clg400-1`): LUT 53,200 / FF 106,400 / DSP 220 / BRAM 140 (36 Kb) |
| CPU | Cortex-A9 × 2 at 650 MHz with NEON |
| Memory | DDR3 512 MB, 16-bit at 1050 MT/s: 2.1 GB/s in theory |
| OS | PYNQ v3.1 image (tested: pynq 3.1.1, Ubuntu 22.04, kernel 6.6.10-xilinx-v2024.1) |

**Measured bandwidth from the fabric** (read-only, AXI DMA into a sink that drops the data, slope method):

| Path | FCLK | Limit of the path | Measured |
|---|---|---|---|
| HP0 | 142.86 MHz | 1.143 GB/s (8 B × FCLK) | 1.143 GB/s |
| HP0 + HP2 | 142.86 MHz | 2.286 GB/s | **2.009 GB/s** (96 % of the DDR's theoretical 2.1) |

One 64-bit stream is capped at 8 bytes per clock. You need two HP ports to reach the DDR's
limit. Use HP0 and HP2: HP0/HP1 and HP2/HP3 share a switch in the PS.

There is no Vivado board file for the PYNQ-Z1. Like PYNQ itself, the designs here use the raw
part number and set all 533 PS7 properties explicitly ([`ps7.tcl`](ps7.tcl), taken from PYNQ's
base overlay).

## Setting up the board (once)

### Jumpers and power

| Jumper | Position | |
|---|---|---|
| JP4 | SD | Boot from the microSD card |
| JP5 | USB | Power from micro-USB J14. Set REG only when you use a 12 V adapter |

Plug J14 (PROG-UART) into the Mac. That powers the board and gives you a serial console
(`screen /dev/cu.usbserial-* 115200`). **With a USB power adapter instead of the Mac, you lose the
serial console.** It is your way back in if the network setup breaks, so keep it for anything
that touches booting or networking. Otherwise, your fallback is to take out the microSD card: the
`/boot` partition is FAT, and macOS can mount it.

Shut down with `sudo shutdown -h now` and wait for the LEDs before switching off. Cutting power
can corrupt the card.

### SSH key login

The image has user `xilinx` with password `xilinx`. Copy your key once:

```bash
ssh-copy-id xilinx@192.168.2.99
```

From then on, `pynq.sh` uses key login. If the key is not the default one, set `PYNQ_SSH_KEY`.

### A fixed IP address

**The PYNQ-Z1 picks a random MAC address at every boot**, so your router's DHCP gives it a new
address every time. Networking is ifupdown. On the board, replace the `eth0` stanza in
`/etc/network/interfaces.d/eth0` with a static one for your LAN, and keep the `eth0:1` alias
(192.168.2.99) that the image ships with. That alias is how you reach the board with a cable
straight from the PC if the LAN setup goes wrong:

```
auto eth0
iface eth0 inet static
    address 192.168.0.50
    netmask 255.255.255.0
    gateway 192.168.0.1
    dns-nameservers 192.168.0.1

auto eth0:1
iface eth0:1 inet static
    address 192.168.2.99
    netmask 255.255.255.0
```

Keep backups **outside** `interfaces.d/`. The `source` line reads every file in that folder, so
a stray `eth0.bak` there gets applied too.

### CMA (contiguous memory for DMA buffers)

`pynq.allocate` takes physically contiguous memory from CMA, which is 128 MB by default
(`CONFIG_CMA_SIZE_MBYTES`, not the device tree). To raise it, add `cma=` to the kernel command
line in `/boot/uEnv.txt`. Build the line from the running kernel's arguments rather than typing it:

```bash
cat /boot/uEnv.txt          # if there is no bootargs= line:
echo "bootargs=$(tr -d '\0' < /proc/device-tree/chosen/bootargs) cma=256M" | sudo tee -a /boot/uEnv.txt
sudo reboot
grep CmaTotal /proc/meminfo # 262144 kB
```

If a `bootargs=` line already exists, append ` cma=256M` to it instead. If the board no longer
boots, put the card in the Mac and remove the line.

### Optional: sudo without a password

`pynq.sh run` uses `sudo`. With a password it asks for it in your terminal, which is fine. For
scripted runs, a file such as `/etc/sudoers.d/010-nopasswd` with mode `0440` works. **The file
name must not contain a dot**, or sudo ignores it. This gives full root over SSH with no password,
so only do it on a test board on a network you trust.

## Building, sending, running

From a project made with `new-project.sh pynq-z1 …`:

```bash
cd my-circuit/hw
vivado.sh build build.tcl bd 100    # always first: ~30 s
vivado.sh build build.tcl all 100   # → out/cumsum100.bit + .hwh

export PYNQ_HOST=xilinx@192.168.0.50
pynq.sh push my-circuit out/cumsum100.bit out/cumsum100.hwh ../host/*
pynq.sh run my-circuit cumsum.py
```

`pynq.sh push DIR FILE…` copies the files to `~/DIR/` on the board. `pynq.sh run DIR SCRIPT ARGS…`
runs `~/DIR/run.sh SCRIPT ARGS…`, which restarts Python as root in a login shell. **Both are needed**:

- writing a bitstream needs root;
- PYNQ's virtual environment and `XILINX_XRT` come from `/etc/profile.d`, which only a login
  shell reads.

`python3 x.py` fails with `Could not open device with index '0'`, and `sudo python3 x.py` fails
with `No module named 'pynq'`.

No JTAG is involved. `Overlay("x.bit")` programs the fabric from Linux and reads `x.hwh` from
the same folder for the address map and clocks. A round trip from editing Verilog to running on
the board takes about 15 minutes, most of it synthesis.

Output of the template at 100 MHz (measured 2026-10-04; WNS +1.507 ns, 9 BRAM tiles, 0 DSP):

```
bitstream: cumsum100.bit  FCLK0: 100.00 MHz
  check         1 beats: all match
  check         7 beats: all match
  check 1,048,576 beats: all match
  check 2,097,152 beats: all match

16 MB: one transfer 21.75 ms, half 11.24 ms
stream throughput (slope): 0.798 GB/s in, the same out
  64-bit stream limit at 100.00 MHz: 0.800 GB/s  (99.8%)
fixed cost per call: 0.73 ms
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Could not open device with index '0'` | Not root. Use `run.sh` / `pynq.sh run` |
| `No module named 'pynq'` | Not a login shell. Use `run.sh` / `pynq.sh run` |
| `validate_bd_design` fails with an unconnected clock on the PS | An AXI port left enabled with nothing attached. Only open the ports you use (`hp_ports` in `build.tcl`) |
| Timing fails at 142.86 MHz in the AXI DMA | Usually the DMA's length counter. Lower `c_sg_length_width`, or use 125 MHz. Two HP ports at 125 MHz (2.000 GB/s) are already at the DDR's limit |
| `transfer`/`wait` never returns | The core never sent TLAST. Every transfer must end with TLAST on the output stream |
| CMA allocation fails although `CmaFree` looks large enough | Fragmentation. Free what you have, `echo 3 > /proc/sys/vm/drop_caches`, allocate in 16 MB pieces, or reboot |
| Board has a different IP every boot | Random MAC address. Set a static address (above) |

More in [lessons learned](../../docs/lessons.md).
