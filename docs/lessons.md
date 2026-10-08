# Lessons learned

[日本語](lessons_ja.md) · [back to fpga-mac](../README.md)

These are mistakes actually made in [fpga-pynq-z1](https://github.com/tsjshg/fpga-pynq-z1), a
ternary LLM running on a PYNQ-Z1. They are rewritten here so they apply to any circuit. Numbers are
measured on a PYNQ-Z1 (XC7Z020 -1) unless noted.

**The three that kept coming back:**

1. data and valid bits going out of step through a pipeline;
2. a fixed per-call cost in the measurement, mistaken for lost bandwidth;
3. a half-hearted CPU baseline.

## Vivado in Docker (macOS)

- **`LD_PRELOAD` is required.** Under Rosetta, Vivado crashes unless `libudev`, `libselinux`,
  `libz` and `libgdk-x11` are preloaded. `vivado.sh` sets this on every call.
- **Use `launch_runs -jobs 2`.** Vivado starts a process of about 2.8 GB per IP. With `-jobs 8`,
  it went past the container's memory (15 GB given to Docker) and the OOM killer stopped it.
- **Split builds into `bd` and `all`, and always run `bd` first.** Checking the block design takes
  30 s to 1 min. Going straight to synthesis takes several minutes to reveal a wiring mistake.
- **Keep the Vivado folder on the internal disk.** It is bind-mounted into the container, and
  file systems without UNIX permissions (exFAT and the like) cause trouble. Docker's own disk
  image works on an external drive. If yours is there, check that the drive is mounted before
  starting Docker.
- **After `open_run`, `get_property STATS.*` returns nothing.** There is only a warning. Read WNS
  before `open_run`, and take resource counts from `report_utilization -file`. Missing this
  nearly hid a DSP count.

## Vivado on x86-64 Linux

- **An install made by vivado-on-silicon-mac can be copied to a Linux machine as is.** It is an
  ordinary x86-64 Linux install. Only the setting scripts (`settings64.sh`, `.settings64-Vivado.sh`
  and the `.csh` versions) hold the absolute install path. `settings64.sh` also sources DocNav,
  Model_Composer and Vitis_HLS. If those weren't copied, remove the lines, or sourcing fails and a
  following `&& vivado` never runs.
- **Ubuntu 24.04 lacks `libtinfo.so.5`.** Vivado 2024.1 stops with
  `couldn't load file "librdi_commontasks.so": libtinfo.so.5`, and xsim too. Vivado bundles the
  library only for RHEL 9 and SUSE. Installing `libtinfo5` and `libncursesw5` from the 22.04
  archive fixes it. `ldd` without Vivado's `LD_LIBRARY_PATH` reports dozens of Vivado's own
  libraries as missing. That is noise; look for system libraries only.
- **LD_PRELOAD is not needed natively.** It works around Rosetta, not Linux.

## Tcl and block designs

- **For a board without a board file, use the part number and configure the PS explicitly.**
  Neither Digilent nor PYNQ provides one for the PYNQ-Z1. Copying the PS7 configuration (533
  properties) from PYNQ's own `base.tcl` works.
- **A borrowed PS configuration leaves unused AXI ports enabled.** Close them explicitly, or
  `validate_bd_design` fails on an unconnected clock.
- **`apply_bd_automation` only wires AXI interfaces.** Connect clock and reset by hand for cells
  joined only by streams. `proc_sys_reset` gets an automatic name, so find it by VLNV
  (`*:proc_sys_reset:*`).
- **Tcl does not substitute variables inside braces.** `-config {… intc_ip $smc …}` passes the
  literal text `$smc` and fails. Build that one line with double quotes.
- **Give your own module's ports explicit `X_INTERFACE_INFO`.** Inference from names sometimes
  fails to group them into a stream interface in IPI.
- **Put one `DONT_TOUCH` register in a stream sink that does nothing.** Without it, synthesis
  removes TDATA as unused, and you can no longer tell whether data really flows.

## Clocks and timing (XC7Z020 -1)

- **FCLK is not what you ask for.** Asking for 150 MHz gives 142.857 MHz (IO PLL 1000 MHz / 7).
  Use the value read back from `PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ` for bandwidth math.
- **AXI DMA with SmartConnect does not close at 200 MHz** (WNS −0.77 ns). 142.86 MHz had margin.
- **When 142.86 MHz fails, look inside the AXI DMA first.** The worst path was almost always the
  S2MM length counter (the carry chain over `c_sg_length_width` bits). The same path varied by
  0.37 ns from placement luck alone. Fixes, in order:
  1. shrink `c_sg_length_width` (23 bits limits a transfer to 8 MiB);
  2. reduce large fan-outs in your own core to ease congestion;
  3. drop to 125 MHz. Two HP ports at 125 MHz give 2.000 GB/s of stream width, about the DDR's
     measured ceiling of 2.009, so a bandwidth-bound circuit loses nothing.
- **Do not put two heavy things in one cycle.** At 142.86 MHz there are 7.00 ns, enough for about
  one small operation. Real failures:
  - distributed-RAM read plus multiply: −0.502 ns;
  - decoding 192 addresses from a beat index: −0.480 ns;
  - 32-bit add, shift, compare and BRAM write: −0.134 ns.

  Area is plentiful, so add pipeline stages from the start.
- **Small multiplies don't go to DSPs on their own.** An 8×8 multiply was built from LUTs with
  four CARRY4s in a row. `(* use_dsp = "yes" *)` on the product register moved it to 10 DSPs and
  WNS went from −0.502 to +0.062 ns.
- **Do not drive the CE of thousands of registers from one net.** With zero logic levels, 93 % of
  the delay (6.3 ns) was routing. `(* max_fanout = 64 *)` lets Vivado replicate it. Bulk clears
  are the same, and can be delayed a cycle. Your own path can pass while the congestion breaks
  someone else's (the DMA's).
- **Variable indices explode routing.** `acc[b*8+i] <= acc[b*8+i] + x` fanned `b` out into a
  192-way address decode. If `b` just steps through in order, rotate the accumulators instead of
  addressing them, so every index is constant. Move the complexity to the path that can be slow
  (reading results out).
- **Check synthesis reports, not assumptions.** A memory expected to bloat into distributed RAM
  had been in BRAM all along (registered read). The fact that a design used 0 DSPs only showed
  up in the report.

## RTL correctness

- **The most repeated mistake: count the stages of the data and of its valid bit, and make them
  match.** Data had 3 stages and valid had 4, so the product of beat b landed in the accumulator
  of beat b−1. Totals are preserved, so "sum everything" checks pass. Only the individual values
  are off by one. A generator script that miscounted its stages produced the same kind of bug.
- **Load an output register only when it is empty or being taken**
  (`load = !m_tvalid || m_tready`). Loading unconditionally drops beats under back-pressure. A deep
  FIFO hides this on the board, so only xsim with back-pressure shows it.
- **Always carry TLAST to the output, even after a partial last group.** If results come out only
  at group boundaries, a transfer with a remainder never delivers TLAST, and the DMA never finishes.
- **Don't read results before the pipeline drains.** Jumping straight to the output state reads
  unfinished accumulators. Add a drain state of a few cycles.
- **Pass xsim before going to the board.** Mix dropped tvalid with tready back-pressure, and hit
  the edges, such as a length-1 packet. One stage cost a full day and three wrong diagnoses on
  hardware. The next one was checked in xsim first and worked the first time. **Find logic errors
  in the simulator. Use the board only for timing and bandwidth.**
- **Compute expected values a different way from the circuit**, e.g. numpy or a plain sum in the
  testbench. Compare every word: totals miss off-by-one-stage bugs.
- **Generate big adder trees and repetitive logic with a script.** Writing a 40-term tree by hand
  goes wrong every time. Don't edit generated `.v` files.
- **When a failure makes no sense, sweep the inputs systematically.** Staring at values didn't
  help. Trying "which output moves when I change input beat b" eight times showed a uniform −1
  right away.

## DMA, HP ports and bandwidth

- **One AXI stream is limited to width × FCLK.** 64 bits at 100 MHz is 0.80 GB/s. A first
  loopback test read as "74 % of DDR" was really each direction sitting at 96 % of its own stream
  width.
- **You need two HP ports to saturate DDR.** Use HP0 and HP2: HP0/HP1 and HP2/HP3 are pairs in the
  PS and congest at the entrance. On the PYNQ-Z1, HP0 alone gave 1.143 GB/s (100 % of the stream
  width) and HP0 + HP2 gave 2.009 GB/s (96 % of the DDR's theoretical peak). Two CPU cores reading
  sequentially reach only 33 %.
- **Measure bandwidth as a slope, not one transfer divided by its time.** PYNQ's
  `transfer`/`wait` costs about 0.7–0.8 ms per channel pair. Time a full and a half transfer and
  divide the difference, and the fixed cost cancels. Not knowing this, a result was reported as
  "98.7 % of the stream width" that was really 100.0 %. **When the numbers don't add up, suspect
  the measurement formula before the circuit.**
- **When splitting work across two ports, keep its order dependencies.** Splitting by buffer sent
  later layers before earlier ones. Splitting each group's rows in half keeps the order.
- **A simple-mode DMA never shows Idle until it has done one transfer.** Waiting for Idle right
  after setting RS=1 waits forever.

## PYNQ (Python on the board)

- **Run as root in a login shell**, for two reasons:
  - writing a bitstream needs root;
  - PYNQ's venv and `XILINX_XRT` come from `/etc/profile.d`, which only a login shell reads.

  Restart with `sudo bash -lc "…"` (the template's `run.sh`).
- **Put `.bit` and `.hwh` side by side with the same basename and load with `Overlay()`.** No
  JTAG needed.
- **For many small transfers, don't use the PYNQ API.**
  - `transfer`/`wait` took 724 µs per call; poking the registers directly took 321 µs. More than
    half is Python.
  - Register access through numpy costs 6–14 µs each.
  - Moving DMA start, wait and copy into C took one token from 177 ms to 126 ms.
- **The number of transfers can become the bottleneck.** The circuit ran at 100 % of its stream
  width, yet the fixed cost of 181 transfers per token took 83 % of the time. Adding a header to
  the stream (row count, row length) so one transfer carries many jobs made it go away. **How you
  feed a circuit can matter more than how fast it is.**
- **Don't slice a `PynqBuffer` repeatedly.** Every slice runs Python's `__array_finalize__`: 100 µs
  each. Take `.view(np.ndarray)` once. `ndarray.ctypes.data` costs 37 µs, so read addresses once.
- **Don't trust CMA numbers. Allocate and see.**
  - With `cma=256M` and `CmaFree` at 233 MB, what could actually be allocated varied from 176 to
    208 MB between runs.
  - One allocation topped out at 160 MB, while 16 MB pieces reached 192 MB.
  - The cause is fragmentation. `drop_caches` first helps a little.
  - The reverse also happens: reloading an Overlay released memory held by DRM, and an allocation
    succeeded although `CmaFree` looked too small.
- **Watch array sizes in numpy on the board.** There is 491 MB of RAM.
  `rng.integers(-1, 2, size=(262139, 640))` with no dtype is int64, 1.25 GB, and it crashed.

## Running the board

- **The PYNQ-Z1 gets a random MAC address at every boot**, so a static IP is a must. A `.bak` file
  in `interfaces.d/` gets applied too.
- **sudo ignores files in `sudoers.d` whose names contain a dot.** Use mode `0440`.
- **Serial doesn't work while powered from an AC adapter.** Power from the Mac over USB, or plan to
  fix `/boot` (FAT) on the Mac. Secure a way back in before changing anything that affects boot.
- **CMA size is one line in `/boot/uEnv.txt`.** It comes from the kernel default, not the device
  tree. Build the bootargs from `/proc/device-tree/chosen/bootargs` instead of typing them.

## Measuring and comparing

- **Label every number as measured or estimated.** Adding up parts measured separately gives an
  estimate.
- **Build the CPU baseline with as much care as the circuit.** A CPU attention baseline compiled
  with `-O2` (no NEON) took 83 ms. Adding `-O3 -mfpu=neon` made it 47 ms, so every earlier "N×
  faster than the CPU" was about 1.8× too high. **Twice in a row, the thing built was measured
  carefully and the thing compared against was not.**
- **To get bit-identical floating point on the Mac and the board, pin the build and the math.**
  - Use `-ffp-contract=off`: clang fuses into FMA by default.
  - No fast-math.
  - Fix the summation order.
  - Write your own `exp` and rounding: `expf` and `rintf` can differ in the last bit between
    libms.
  - Avoid `vrecpsq_f32`, which is fused on AArch64.

  With that, results matched bit for bit between the ARMv7 board and Apple Silicon.
