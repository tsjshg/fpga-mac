# fpga-mac

[English](README.md)

Apple Silicon の Mac で FPGA の回路を作り、Zynq のボードで動かすまでを、すべてコマンドラインで行うための道具一式です。

Vivado が動くのは x86-64 の Linux と Windows で、macOS では動きません。ここでは GUI なしの batch モードで、Mac の上の Docker と Rosetta 2 の中で動かすか、Mac からビルドを送る x86-64 の Linux マシンで動かします。このリポジトリには、そのまわりで要るものを置いています。

- `vivado.sh`: プロジェクトの Tcl のビルドや xsim を、Docker の中・Linux の上・SSH 越しの Linux のビルド用マシンのどれかで走らせる
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

`vivado.sh` は、Vivado を次の3通りのどれかで動かします。どれになるかは自動で決まります。

| 動かし方 | いつ | どうやって |
|---|---|---|
| docker | macOS の上（既定） | Rosetta 2 の上の Docker コンテナの中で |
| local | x86-64 の Linux の上 | そのまま |
| remote | `VIVADO_HOST` を設定したとき | 今いる場所を SSH で x86-64 の Linux に送ってそこで動かし、`out/` を持ち帰る |

| コマンド | 内容 |
|---|---|
| `vivado.sh start` | docker: コンテナ `vivado_<プロジェクト名>` を立て、プロジェクトを `/work` に載せる。local・remote: Vivado が起動するか確かめる |
| `vivado.sh build X.tcl 引数…` | `vivado -mode batch -source X.tcl -tclargs 引数…` |
| `vivado.sh sh 'コマンド'` | Vivado の環境を読み込んだうえでシェルのコマンドを実行（xsim など） |
| `vivado.sh status` | docker: 動いている `vivado_*` コンテナの一覧。それ以外: どこで動かすか |
| `vivado.sh stop` | docker: このプロジェクトのコンテナを止める |

「プロジェクト」は、今いる場所の git リポジトリのてっぺんです（git の外なら今いる場所）。

- **docker**: コマンドはコンテナの中の対応する場所で走るので、`hw/` から叩けば Tcl の相対パスがそのまま通ります。コンテナはプロジェクトごとに別なので、いくつ同時に動かしても構いません。VNC は使わず、vivado-on-silicon-mac の GUI 用コンテナとも干渉しません。
- **remote**: 今いる場所の中身を、送り先の `~/fpga-work/<プロジェクト名>/<てっぺんからの相対パス>/` に rsync で写します。`.git/`・`prj_*/`・`.Xil/`・`sim/work/` は送りません。持ち帰るのは `out/` だけです。`hw/` のように、ビルドに要るものが全部入った場所から叩いてください。

| 環境変数 | 既定値 | |
|---|---|---|
| `VIVADO_VER` | `2024.1` | |
| `VIVADO_MAC` | `~/tools/vivado-on-silicon-mac-main` | docker: `Xilinx/Vivado/<版>` が入っているフォルダ |
| `VIVADO_DIR` | `/tools/Xilinx` | local・remote: Linux のマシンでの Xilinx のインストール先 |
| `VIVADO_HOST` | | remote: `user@host` |
| `VIVADO_SSH_KEY` | | remote: 鍵ファイル（`~/.ssh/config` に書いていないとき） |
| `FPGA_ROOT` | git のてっぺん、または今いる場所 | プロジェクトのてっぺん |

### x86-64 の Linux でビルドする

Vivado は x86-64 の Linux ならそのまま動き、Rosetta も Docker も要りません。古い Intel の Mac mini に Ubuntu を入れれば、Apple Silicon の Mac からビルドを送る先として使えます。

1. そのマシンに Vivado 2024.1 を入れます。vivado-on-silicon-mac が入れた中身はふつうの x86-64 Linux 用なので、Mac から `Xilinx/Vivado/2024.1` を写しても構いません（32 GB。ギガビットの有線 LAN で 10 分ほど）。無償版なのでライセンスファイルは要りません。写したあとは、次の2つをしてください。
   - `settings64.sh`・`.settings64-Vivado.sh` と、それぞれの `.csh` 版で、`/home/user/Xilinx` を新しい場所に書き換える
   - DocNav・Model_Composer・Vitis_HLS を写していなければ、`settings64.sh` からそれらを読み込む行を消す
2. **Ubuntu 24.04 では**、Vivado 2024.1 が使う `libtinfo.so.5` がもう入っていません。Vivado 本体も xsim も `libtinfo.so.5: cannot open shared object file` で止まります。22.04 のパッケージを Ubuntu のアーカイブから入れてください。

   ```bash
   cd /tmp && wget http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.3_amd64.deb http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.3_amd64.deb
   sudo apt install /tmp/libtinfo5_6.3-2ubuntu0.3_amd64.deb /tmp/libncursesw5_6.3-2ubuntu0.3_amd64.deb
   ```

3. Mac から次のように叩きます。

   ```bash
   export VIVADO_HOST=builder@192.168.0.50   # 自分の Linux のマシン
   cd my-circuit/hw
   vivado.sh start                           # Vivado の版が出る
   vivado.sh build build.tcl all 100         # → Mac の out/ にできる
   ```

   PYNQ-Z1 のひな形を 100 MHz でビルドした実測では、2018 年の Mac mini（Core i7-8700B・32 GB・Ubuntu 24.04）が送り迎え込みで 6 分 37 秒でした。M4 の Mac の Docker では約 9 分です。

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
vivado.sh                 Vivado を Docker の中で / Linux で / 別の Linux マシンで
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
