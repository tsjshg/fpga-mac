#!/bin/zsh
# Vivado を batch で叩く入口。動かし方は3通りあり、自動で選ぶ:
#   docker  macOS（Apple Silicon）: Docker + Rosetta 2 のコンテナの中で
#   local   x86-64 の Linux の上: そのまま
#   remote  VIVADO_HOST を設定したとき: ssh で x86-64 の Linux に送って、そこで
#
#   vivado.sh start                         docker: コンテナを立てる / remote: つながるか確かめる
#   vivado.sh build build.tcl bd 100        vivado -mode batch -source build.tcl -tclargs bd 100
#   vivado.sh sh 'sim/run.sh'               Vivado の環境で任意のコマンド（xsim など）
#   vivado.sh status                        動いているコンテナ / 送り先
#   vivado.sh stop                          docker: コンテナを止める
#
# docker: 今いる場所の git リポジトリのてっぺん（git の外なら今の場所）をコンテナの /work に
#   載せ、今いる場所に対応する /work/... で実行する。コンテナ名は vivado_<プロジェクト名>。
# remote: 今いる場所の中身を送り先の ~/fpga-work/<プロジェクト名>/<てっぺんからの相対パス>/ に
#   rsync で送って実行し、終わったら out/ だけを持ち帰る。.git/ prj_*/ .Xil/ sim/work/ は送らない。
#   だから hw/ のように、ビルドに要るものが全部入った場所から叩くこと。
#
# 環境変数:
#   VIVADO_VER      版（既定 2024.1）
#   VIVADO_MAC      docker: Vivado の入ったフォルダ（既定 ~/tools/vivado-on-silicon-mac-main）
#   VIVADO_DIR      local / remote: Xilinx のインストール先（既定 /tools/Xilinx）
#   VIVADO_HOST     remote: user@host
#   VIVADO_SSH_KEY  remote: 鍵ファイル（~/.ssh/config に書いていないとき）
#   FPGA_ROOT       プロジェクトのてっぺんを明示したいとき

VIVADO_VER=${VIVADO_VER:-2024.1}
VIVADO_MAC=${VIVADO_MAC:-$HOME/tools/vivado-on-silicon-mac-main}
VIVADO_DIR=${VIVADO_DIR:-/tools/Xilinx}
ROOT=${FPGA_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
ROOT=${ROOT:A}
HERE=${PWD:A}
case $HERE/ in
  $ROOT/*) REL=${HERE#$ROOT} ;;
  *) echo "the current directory is outside the project: $ROOT" >&2; exit 1 ;;
esac
PROJ=${${ROOT:t}//[^A-Za-z0-9_.-]/_}

if   [[ -n $VIVADO_HOST ]];    then MODE=remote
elif [[ $(uname) == Linux ]];  then MODE=local
else                                MODE=docker
fi

# ---------- docker ----------
NAME=vivado_$PROJ
# Rosetta 下では、これらを先に読み込んでおかないと Vivado が落ちる。
PRE_DOCKER="export LD_PRELOAD='/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libgdk-x11-2.0.so.0'; source /home/user/Xilinx/Vivado/$VIVADO_VER/settings64.sh; cd /work$REL"
running() { docker ps --format '{{.Names}}' | grep -qx $NAME }
need() { running || { echo "$NAME is not running. Run: vivado.sh start" >&2; exit 1 } }

# ---------- local / remote ----------
SETTINGS=$VIVADO_DIR/Vivado/$VIVADO_VER/settings64.sh
RDIR=fpga-work/$PROJ$REL
sshv=(ssh -o ConnectTimeout=10)
[[ -n $VIVADO_SSH_KEY ]] && sshv+=(-i $VIVADO_SSH_KEY)
EXCL=(--exclude .git/ --exclude 'prj_*/' --exclude .Xil/ --exclude sim/work/ --exclude .DS_Store)

# remote で1つのコマンドを走らせる: 送る → 実行 → out/ を持ち帰る
remote() {
  local script="source $SETTINGS && cd ~/$RDIR && $1" rc
  $sshv $VIVADO_HOST "mkdir -p ~/$RDIR" &&
    rsync -a $EXCL -e "${sshv[*]}" ./ "$VIVADO_HOST:$RDIR/" || { echo "failed to send to $VIVADO_HOST" >&2; return 1 }
  $sshv $VIVADO_HOST "bash -c ${(qq)script}"; rc=$?
  if $sshv $VIVADO_HOST "test -d ~/$RDIR/out"; then
    mkdir -p out && rsync -a -e "${sshv[*]}" "$VIVADO_HOST:$RDIR/out/" out/
  fi
  return $rc
}

run() {  # $1 = Vivado の環境で走らせるシェルのコマンド
  case $MODE in
    docker) need; docker exec -u user $NAME bash -lc "$PRE_DOCKER && $1" ;;
    local)  [[ -f $SETTINGS ]] || { echo "Vivado $VIVADO_VER not found: $SETTINGS" >&2; exit 1 }
            bash -c "source $SETTINGS && $1" ;;
    remote) remote "$1" ;;
  esac
}

case "$1" in
  start)
    case $MODE in
      docker)
        [[ -d $VIVADO_MAC/Xilinx/Vivado/$VIVADO_VER ]] || { echo "Vivado $VIVADO_VER not found in $VIVADO_MAC" >&2; exit 1 }
        running && { echo "$NAME is already running (/work = $ROOT)"; exit 0 }
        docker run -d --init --rm --name $NAME \
          --mount type=bind,source="$VIVADO_MAC",target=/home/user \
          --mount type=bind,source="$ROOT",target=/work \
          --platform linux/amd64 x64-linux sleep infinity >/dev/null &&
          echo "$NAME started (/work = $ROOT)" ;;
      local)  run 'vivado -version 2>/dev/null | grep -m1 ^vivado' ;;
      remote) $sshv $VIVADO_HOST "bash -c ${(qq):-source $SETTINGS && vivado -version 2>/dev/null | grep -m1 ^vivado}" &&
              echo "remote: $VIVADO_HOST:~/$RDIR" ;;
    esac ;;
  build)
    shift; tcl=$1; shift
    run "vivado -mode batch -nojournal -notrace -source $tcl -tclargs $*" ;;
  sh)
    shift; run "$*" ;;
  status)
    case $MODE in
      docker) docker ps --filter name=vivado_ --format '{{.Names}}\t{{.Status}}\t{{.Mounts}}' ;;
      *)      echo "$MODE: ${VIVADO_HOST:-this machine}, Vivado $VIVADO_VER in $VIVADO_DIR" ;;
    esac ;;
  stop)
    case $MODE in
      docker) docker kill $NAME >/dev/null && echo "$NAME stopped" ;;
      *)      echo "$MODE mode: nothing to stop" ;;
    esac ;;
  *)
    sed -n '2,27p' "$0"; exit 1 ;;
esac
