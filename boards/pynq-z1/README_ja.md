# PYNQ-Z1

[English](README.md) · [fpga-mac に戻る](../../README_ja.md)

| | |
|---|---|
| FPGA | Zynq XC7Z020（`xc7z020clg400-1`）: LUT 53,200 / FF 106,400 / DSP 220 / BRAM 140（36 Kb） |
| CPU | Cortex-A9 × 2、650 MHz、NEON あり |
| メモリ | DDR3 512 MB。16 bit・1050 MT/s で理論 2.1 GB/s |
| OS | PYNQ v3.1 のイメージ（確認した版: pynq 3.1.1、Ubuntu 22.04、kernel 6.6.10-xilinx-v2024.1） |

**ファブリックから DDR を読む帯域の実測値**です。読むだけの条件で、AXI DMA の先に受け取って捨てるだけの回路を置き、傾きで測りました。

| 経路 | FCLK | 経路の上限 | 実測 |
|---|---|---|---|
| HP0 | 142.86 MHz | 1.143 GB/s（8 B × FCLK） | 1.143 GB/s |
| HP0 + HP2 | 142.86 MHz | 2.286 GB/s | **2.009 GB/s**（DDR の理論値 2.1 の 96%） |

64 bit のストリームは1本あたり 1 クロック 8 バイトが上限です。DDR の上限まで使うには HP ポートが2本要ります。使うのは HP0 と HP2 にしてください。PS の中で HP0/HP1、HP2/HP3 がそれぞれ同じスイッチを共有しているからです。

PYNQ-Z1 には Vivado のボードファイルがありません。そこで PYNQ 自身と同じく、生の部品番号を指定し、PS7 の 533 項目をすべて明示的に設定します（[`ps7.tcl`](ps7.tcl)。PYNQ の base overlay から取ったもの）。

## ボードの準備（初回だけ）

### ジャンパと電源

| ジャンパ | 位置 | |
|---|---|---|
| JP4 | SD | microSD から起動する |
| JP5 | USB | micro-USB（J14）から給電。12 V の AC アダプタを使うときだけ REG |

J14（PROG-UART）を Mac につなぎます。電源が入るうえ、シリアルコンソールも使えます（`screen /dev/cu.usbserial-* 115200`）。**Mac ではなく USB 電源アダプタにつなぐと、シリアルは使えません。** シリアルは、ネットワークの設定を壊したときにボードへ戻るための道です。起動やネットワークに関わる作業は、シリアルを確保してから行ってください。シリアルが無いときの退路は、microSD を抜くことです。`/boot` は FAT なので、Mac にそのまま挿して直せます。

電源を切るときは `sudo shutdown -h now` を実行し、LED が消えてから切ります。いきなり切ると microSD が壊れることがあります。

### SSH の鍵ログイン

イメージにはユーザ `xilinx`（パスワード `xilinx`）がいます。最初に一度だけ鍵を登録します。

```bash
ssh-copy-id xilinx@192.168.2.99
```

以後、`pynq.sh` は鍵でログインします。既定以外の鍵を使うなら、`PYNQ_SSH_KEY` に指定してください。

### IP アドレスの固定

**PYNQ-Z1 は起動のたびに MAC アドレスをランダムに作ります。** そのため、ルータの DHCP では毎回違うアドレスになります。ネットワークの設定は ifupdown です。ボードの `/etc/network/interfaces.d/eth0` の `eth0` の部分を、自分の LAN に合わせた固定設定に書き換えてください。イメージに最初から入っている `eth0:1`（192.168.2.99）は残します。LAN 側の設定を誤ったとき、PC とケーブルで直結して入れる唯一の道です。

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

退避用のコピーは **`interfaces.d/` の外**に置いてください。`source` の行はこのフォルダの中のファイルを拡張子を問わず全部読むので、`eth0.bak` を置くとそれも適用されてしまいます。

### CMA（DMA バッファ用の連続メモリ）

`pynq.allocate` は物理的に連続したメモリを CMA から取ります。CMA は既定で 128 MB で、デバイスツリーではなくカーネルの `CONFIG_CMA_SIZE_MBYTES` で決まっています。増やすには、`/boot/uEnv.txt` のカーネル引数に `cma=` を足します。引数は手で打たず、いま動いているカーネルの引数から作ってください。

```bash
cat /boot/uEnv.txt          # bootargs= の行が無ければ:
echo "bootargs=$(tr -d '\0' < /proc/device-tree/chosen/bootargs) cma=256M" | sudo tee -a /boot/uEnv.txt
sudo reboot
grep CmaTotal /proc/meminfo # 262144 kB
```

`bootargs=` の行がすでにあるときは、その行の末尾に ` cma=256M` を足してください。起動しなくなったら、microSD を Mac に挿してその行を消せば戻ります。

### 任意: パスワードなしの sudo

`pynq.sh run` は `sudo` を使います。パスワードが要る設定なら端末で聞かれるので、そのままでも使えます。スクリプトから回したいなら、`/etc/sudoers.d/010-nopasswd` のようなファイルを権限 `0440` で置く方法があります。**ファイル名にドットを含めると sudo に無視されます。** これは SSH 越しにパスワードなしで root を渡すことになります。信頼できるネットワークにあるテスト用のボードだけにしてください。

## ビルド・送る・動かす

`new-project.sh pynq-z1 …` で作ったプロジェクトで、次のように実行します。

```bash
cd my-circuit/hw
vivado.sh build build.tcl bd 100    # 必ず先に。30 秒ほど
vivado.sh build build.tcl all 100   # → out/cumsum100.bit と .hwh

export PYNQ_HOST=xilinx@192.168.0.50
pynq.sh push my-circuit out/cumsum100.bit out/cumsum100.hwh ../host/*
pynq.sh run my-circuit cumsum.py
```

`pynq.sh push DIR ファイル…` は、ボードの `~/DIR/` にファイルを送ります。`pynq.sh run DIR スクリプト 引数…` は `~/DIR/run.sh スクリプト 引数…` を実行し、そこで Python を root・ログインシェルで起動し直します。**両方の条件が要ります。**

- ビットストリームを書き込むには root が要る
- PYNQ の仮想環境と `XILINX_XRT` は `/etc/profile.d` で設定されるので、ログインシェルでないと入らない

`python3 x.py` とだけ打つと `Could not open device with index '0'` で落ちます。`sudo python3 x.py` では `No module named 'pynq'` で落ちます。

JTAG は使いません。`Overlay("x.bit")` が Linux からファブリックに書き込み、同じフォルダの `x.hwh` からアドレスとクロックを読みます。Verilog を直してから実機で動くまで、一周およそ 15 分です。そのほとんどは合成の時間です。

ひな形を 100 MHz で動かしたときの出力です（2026-10-04 の実測。WNS +1.507 ns、BRAM 9 タイル、DSP 0）。

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

## 困ったとき

| 症状 | 原因と対処 |
|---|---|
| `Could not open device with index '0'` | root でない。`run.sh` / `pynq.sh run` を使う |
| `No module named 'pynq'` | ログインシェルでない。`run.sh` / `pynq.sh run` を使う |
| `validate_bd_design` が PS のクロック未接続で落ちる | 何もつないでいない AXI ポートが開いたまま。使うポートだけ開ける（`build.tcl` の `hp_ports`） |
| 142.86 MHz で AXI DMA の中がタイミング違反 | たいてい DMA の転送長カウンタ。`c_sg_length_width` を縮めるか、125 MHz にする。HP 2本・125 MHz（2.000 GB/s）でもう DDR の上限に届いている |
| `transfer`/`wait` が戻ってこない | 回路が TLAST を出していない。出力のストリームは、転送ごとに必ず TLAST で終える |
| `CmaFree` は足りて見えるのに CMA が取れない | 断片化。取った分を返し、`echo 3 > /proc/sys/vm/drop_caches` をしてから 16 MB ずつ取るか、再起動する |
| 起動のたびに IP が変わる | MAC がランダム。上の手順でアドレスを固定する |

ほかの罠は[踏んだ罠と対処](../../docs/lessons_ja.md)にまとめています。
