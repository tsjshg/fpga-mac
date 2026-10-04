#!/bin/zsh
# Vivado（Docker + Rosetta 2）を macOS から batch で叩く入口。
#
#   vivado.sh start                         いまのプロジェクトのコンテナを立てる（数秒）
#   vivado.sh build build.tcl bd 100        vivado -mode batch -source build.tcl -tclargs bd 100
#   vivado.sh sh 'cd sim && ./run.sh'       コンテナの中で任意のコマンド（xsim など）
#   vivado.sh status                        動いているコンテナの一覧
#   vivado.sh stop                          いまのプロジェクトのコンテナを止める
#
# 「プロジェクト」は今いる場所の git リポジトリのてっぺん（git の外なら今の場所）。
# そこをコンテナの /work に載せ、今いる場所に対応する /work/... で実行する。
# だから hw/ に cd してから叩けば、Tcl の相対パスは hw/ から解決される。
# コンテナ名は vivado_<プロジェクト名> なので、別のプロジェクトのものと同時に動いてよい。
#
# 環境変数:
#   VIVADO_MAC   Vivado の入ったフォルダ（既定 ~/tools/vivado-on-silicon-mac-main）
#   VIVADO_VER   版（既定 2024.1）
#   FPGA_ROOT    プロジェクトのてっぺんを明示したいとき

VIVADO_MAC=${VIVADO_MAC:-$HOME/tools/vivado-on-silicon-mac-main}
VIVADO_VER=${VIVADO_VER:-2024.1}
ROOT=${FPGA_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
ROOT=${ROOT:A}
HERE=${PWD:A}
case $HERE/ in
  $ROOT/*) REL=${HERE#$ROOT} ;;
  *) echo "the current directory is outside the project: $ROOT" >&2; exit 1 ;;
esac
NAME=vivado_${${ROOT:t}//[^A-Za-z0-9_.-]/_}

# Rosetta 下では、これらを先に読み込んでおかないと Vivado が落ちる。
PRE="export LD_PRELOAD='/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libgdk-x11-2.0.so.0'; source /home/user/Xilinx/Vivado/$VIVADO_VER/settings64.sh; cd /work$REL"

running() { docker ps --format '{{.Names}}' | grep -qx $NAME }
need() { running || { echo "$NAME is not running. Run: vivado.sh start" >&2; exit 1 } }

case "$1" in
  start)
    [[ -d $VIVADO_MAC/Xilinx/Vivado/$VIVADO_VER ]] || { echo "Vivado $VIVADO_VER not found in $VIVADO_MAC" >&2; exit 1 }
    running && { echo "$NAME is already running (/work = $ROOT)"; exit 0 }
    docker run -d --init --rm --name $NAME \
      --mount type=bind,source="$VIVADO_MAC",target=/home/user \
      --mount type=bind,source="$ROOT",target=/work \
      --platform linux/amd64 x64-linux sleep infinity >/dev/null &&
      echo "$NAME started (/work = $ROOT)" ;;
  build)
    need; shift; tcl=$1; shift
    docker exec -u user $NAME bash -lc "$PRE && vivado -mode batch -nojournal -notrace -source $tcl -tclargs $*" ;;
  sh)
    need; shift
    docker exec -u user $NAME bash -lc "$PRE && $*" ;;
  status)
    docker ps --filter name=vivado_ --format '{{.Names}}\t{{.Status}}\t{{.Mounts}}' ;;
  stop)
    docker kill $NAME >/dev/null && echo "$NAME stopped" ;;
  *)
    sed -n '2,19p' "$0"; exit 1 ;;
esac
