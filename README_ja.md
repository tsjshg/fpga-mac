# fpga-mac

[English](README.md)

Apple Silicon の Mac で FPGA の回路を作り、Zynq のボードで動かすまでを、すべてコマンドラインで行うための道具一式です。

Vivado は x86 Linux でしか動きません。ここでは Docker と Rosetta 2 の上で、GUI なしの batch モードで動かします。このリポジトリには、そのまわりで要るものを置いています。

- `vivado.sh`: プロジェクトごとにコンテナを立て、その中で Tcl のビルドや xsim を走らせる
- `new-project.sh`: ボードのひな形から新しいプロジェクトを作る。ひな形はそのままでシミュレーション・ビルド・実機での実行まで通る
- ボードごとのファイル: PS の設定、ボードへ送って動かすスクリプト、ひな形
- [踏んだ罠と対処](docs/lessons_ja.md): Docker の中の Vivado、タイミング、AXI、DMA、PYNQ、それに自分をだまさない測り方

対応しているボード:

| ボード | FPGA | 備考 |
|---|---|---|
| [PYNQ-Z1](boards/pynq-z1/README_ja.md) | Zynq XC7Z020 | PYNQ v3.1 のイメージ。HP0/HP2 で DDR3 に約 2.0 GB/s（実測） |

この仕組みは [fpga-pynq-z1](https://github.com/tsjshg/fpga-pynq-z1) から切り出したものです。fpga-pynq-z1 では、三値の LLM（BitNet b1.58）を PYNQ-Z1 の FPGA に自作した回路で動かしています。

## 全体の流れ

```
 Mac                                                     ボード (PYNQ-Z1)
 --------------------------------------------------      ------------------------
 自分のプロジェクト/                                     ~/自分のプロジェクト/
   hw/rtl/*.v -- sim/run.sh --> xsim        +            *.bit + *.hwh
   hw/build.tcl -- bd --> BD の検証         | Docker     host/*.py --> Overlay()
              `-- all --> out/*.bit, *.hwh +(Vivado)     run.sh (root・ログインシェル)
   host/*.py                                                   ^
        `----------- boards/pynq-z1/pynq.sh push / run --------+  (ssh, scp)
```

## 必要なもの

| | |
|---|---|
| Mac | Apple Silicon。macOS 15 で確認（[vivado-on-silicon-mac](https://github.com/ichi4096/vivado-on-silicon-mac) は macOS 14 の大半に非対応） |
| Docker Desktop | Apple Silicon 版。メモリは 15 GB ほど割り当てる（Vivado は IP ごとに約 2.8 GB のプロセスを立てる） |
| ディスク | Vivado 2024.1（Zynq-7000 と Zynq UltraScale+ 入り）で約 45 GB |
| Vivado | 2024.1。XC7Z020 は無償の Standard 版で使える |

## 準備（初回だけ）

### 1. vivado-on-silicon-mac で Vivado を入れる

[ichi4096/vivado-on-silicon-mac](https://github.com/ichi4096/vivado-on-silicon-mac) の手順どおりに入れます。Docker のイメージ `x64-linux` が作られ、Vivado はそのツールのフォルダの中に入ります。フォルダは `~/tools/vivado-on-silicon-mac-main` に置くか、別の場所なら環境変数 `VIVADO_MAC` で指定してください。

- フォルダは内蔵ディスクに置いてください。コンテナに bind mount で見せるためです。exFAT などの外付けディスクは UNIX の権限を持てません。
- インストールが終わったら、インストーラとツールの `work` フォルダは消して構いません。

### 2. このリポジトリを clone する

```bash
git clone https://github.com/tsjshg/fpga-mac.git ~/fpga-mac
```

`PATH` に足しておくと、`vivado.sh` と `new-project.sh` をどこからでも叩けます。

### 3. ボードを準備する

ボードごとのページを見てください（[PYNQ-Z1](boards/pynq-z1/README_ja.md) なら、SSH の鍵ログイン、IP の固定、CMA の大きさ）。

## プロジェクトを始める

```bash
~/fpga-mac/new-project.sh pynq-z1 ~/my-circuit
cd ~/my-circuit/hw
~/fpga-mac/vivado.sh start                   # このプロジェクト用のコンテナ（数秒）
~/fpga-mac/vivado.sh sh 'sim/run.sh'         # xsim。入力の途切れと背圧をかけて → PASS
~/fpga-mac/vivado.sh build build.tcl bd      # ブロックデザインの検証（30 秒ほど）
~/fpga-mac/vivado.sh build build.tcl all     # 合成〜ビットストリーム（10 分ほど）
```

できたプロジェクトは自己完結しています。ボードの PS 設定も写してあるので、fpga-mac が無くても Vivado さえあれば作り直せます（`vivado -mode batch -source build.tcl`）。その代わり、fpga-mac 側を直しても、作ったあとのプロジェクトには反映されません。

ボードへ送って動かす手順は、ボードのページに詳しく書いています。

```bash
export PYNQ_HOST=xilinx@192.168.2.99        # 自分のボード
~/fpga-mac/boards/pynq-z1/pynq.sh push my-circuit out/cumsum100.bit out/cumsum100.hwh ../host/*
~/fpga-mac/boards/pynq-z1/pynq.sh run my-circuit cumsum.py
```

## `vivado.sh`

| コマンド | 内容 |
|---|---|
| `vivado.sh start` | コンテナ `vivado_<プロジェクト名>` を立て、プロジェクトを `/work` に載せる |
| `vivado.sh build X.tcl 引数…` | `vivado -mode batch -source X.tcl -tclargs 引数…` |
| `vivado.sh sh 'コマンド'` | Vivado の環境を読み込んだうえでシェルのコマンドを実行（xsim など） |
| `vivado.sh status` | 動いている `vivado_*` コンテナの一覧 |
| `vivado.sh stop` | このプロジェクトのコンテナを止める |

「プロジェクト」は、今いる場所の git リポジトリのてっぺんです（git の外なら今いる場所）。コマンドはコンテナの中の対応する場所で走るので、`hw/` から叩けば Tcl の相対パスがそのまま通ります。コンテナはプロジェクトごとに別なので、いくつ同時に動かしても構いません。VNC は使わず、vivado-on-silicon-mac の GUI 用コンテナとも干渉しません。

| 環境変数 | 既定値 | |
|---|---|---|
| `VIVADO_MAC` | `~/tools/vivado-on-silicon-mac-main` | `Xilinx/Vivado/<版>` が入っているフォルダ |
| `VIVADO_VER` | `2024.1` | |
| `FPGA_ROOT` | git のてっぺん、または今いる場所 | `/work` に載せるフォルダ |

## ボードを足すとき

1. `boards/<ボード名>/` を作り、次のものを置きます。
   - ボードの PS 設定またはピン設定
   - ボードへ送って動かすスクリプト
   - `README.md` と `README_ja.md`
   - そのボードでビルド・シミュレーション・実行まで通る `template/`
2. ひな形をまっさらな状態から試します。`new-project.sh` → xsim → `bd` → `all` → 実機、の順です。
3. 上の表と [README.md](README.md) に足します。わかったことは [docs/lessons_ja.md](docs/lessons_ja.md) と [docs/lessons.md](docs/lessons.md) に書き足します。

## ファイル構成

```
vivado.sh                 Docker の中の Vivado: start / build / sh / status / stop
new-project.sh            boards/<ボード>/template から新しいプロジェクトを作る
docs/lessons.md           踏んだ罠と対処（英語）
docs/lessons_ja.md        同じものの日本語版
boards/pynq-z1/
  README.md, README_ja.md ボードの準備・送り方・困ったとき
  ps7.tcl                 Zynq PS7 の設定（PYNQ の base overlay から）
  pynq.sh                 ボードへファイルを送る / root でスクリプトを動かす
  template/               DMA → 自作の AXI4-Stream 回路 → DMA。xsim の検証とボード用スクリプトつき
```

## ライセンス

BSD 3-Clause（[LICENSE](LICENSE)）です。`boards/pynq-z1/ps7.tcl` の PS7 設定は Xilinx/PYNQ のもので、同じ BSD 3-Clause ですが、著作権表示は Xilinx のものになります（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)）。Vivado 本体は AMD のソフトウェアで、AMD のライセンスに従います。このリポジトリには含まれていません。
