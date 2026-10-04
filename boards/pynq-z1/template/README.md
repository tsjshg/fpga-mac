# my-circuit

A PYNQ-Z1 project started from [fpga-mac](https://github.com/tsjshg/fpga-mac)'s template.
Rename it and replace `axis_cumsum` with your own circuit.

[fpga-mac](https://github.com/tsjshg/fpga-mac) のひな形から始めた PYNQ-Z1 のプロジェクトです。
名前を変えて、`axis_cumsum` を自分の回路に置き換えてください。

```
hw/rtl/axis_cumsum.v       the circuit: running sum per 32-bit lane, reset at TLAST
hw/sim/tb_axis_cumsum.v    xsim test with dropped tvalid and back-pressure; run: hw/sim/run.sh
hw/build.tcl               PS7 + AXI DMA (HP0) + the circuit. Args: bd|all [FCLK MHz]
hw/ps7.tcl                 PYNQ-Z1 PS7 configuration (BSD-3 part from Xilinx/PYNQ, see header)
host/cumsum.py             on the board: load, run, compare with numpy, measure bandwidth
host/run.sh                on the board: restart a script as root in a login shell
```

```bash
cd hw
vivado.sh start
vivado.sh sh 'sim/run.sh'                 # PASS
vivado.sh build build.tcl bd 100          # block design check
vivado.sh build build.tcl all 100         # → out/cumsum100.bit + .hwh
pynq.sh push my-circuit out/cumsum100.bit out/cumsum100.hwh ../host/*
pynq.sh run my-circuit cumsum.py
```

Without fpga-mac, Vivado 2024.1 alone builds it: `cd hw && vivado -mode batch -source build.tcl -tclargs all 100`.
