# Third-party notices

[LICENSE](LICENSE) (BSD 3-Clause, Copyright (c) 2026, Shingo Tsuji) covers the code and documents
written for this repository. The items below have other copyright holders or terms.

## PYNQ-Z1 PS7 configuration (Xilinx/PYNQ, BSD 3-Clause)

The first `set_property` block in `boards/pynq-z1/ps7.tcl` holds the Zynq PS7 configuration
properties of the PYNQ-Z1 base overlay, taken unchanged from
[`boards/Pynq-Z1/base/base.tcl`](https://github.com/Xilinx/PYNQ/blob/v3.1/boards/Pynq-Z1/base/base.tcl)
in [Xilinx/PYNQ](https://github.com/Xilinx/PYNQ). `new-project.sh` copies this file into new
projects, and the file carries the notice below in its header so the notice travels with every copy.

```
Copyright (c) 2016-2021, Xilinx, Inc.
SPDX-License-Identifier: BSD-3-Clause

BSD 3-Clause License

Copyright (c) 2018, Xilinx
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Vivado

Vivado and the AMD IP it adds to a design (Zynq-7000 processing system, AXI DMA, AXI SmartConnect,
AXI Interconnect, Processor System Reset, and others) are AMD's, under AMD's license terms. None of
it is in this repository. Bitstreams and other files that Vivado generates from these designs
contain that IP and remain subject to those terms.
