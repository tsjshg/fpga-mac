#!/bin/zsh
# Mac から PYNQ-Z1 へ送って動かす。
#
#   pynq.sh push DIR FILE...        ボードの ~/DIR/ にファイルを送る（DIR は無ければ作る）
#   pynq.sh run DIR SCRIPT [ARGS]   ~/DIR/run.sh SCRIPT ARGS（root・ログインシェルで python3）
#   pynq.sh ssh [COMMAND]           ボードにログイン、またはコマンドを1つ実行
#
# 環境変数:
#   PYNQ_HOST     user@host（必須。例 xilinx@192.168.2.99）
#   PYNQ_SSH_KEY  鍵ファイル（~/.ssh/config に書いていないとき）
#
# run は sudo を使う。パスワードが要る設定なら端末で叩くこと（-t で端末を割り当てる）。

: ${PYNQ_HOST:?set PYNQ_HOST=user@host}
opts=(-o ConnectTimeout=10)
[[ -n $PYNQ_SSH_KEY ]] && opts+=(-i $PYNQ_SSH_KEY)
tty=(); [[ -t 0 ]] && tty=(-t)

case "$1" in
  push)
    (( $# >= 3 )) || { echo "usage: pynq.sh push DIR FILE..." >&2; exit 1 }
    dir=$2; shift 2
    ssh $opts $PYNQ_HOST "mkdir -p ${(q)dir}" &&
      scp -q $opts "$@" "$PYNQ_HOST:$dir/" &&
      echo "sent $# file(s) to $PYNQ_HOST:~/$dir/" ;;
  run)
    (( $# >= 3 )) || { echo "usage: pynq.sh run DIR SCRIPT [ARGS...]" >&2; exit 1 }
    dir=$2; shift 2
    ssh $opts $tty $PYNQ_HOST "cd ${(q)dir} && ./run.sh ${(j: :)${(qq)@}}" ;;
  ssh)
    shift
    ssh $opts $tty $PYNQ_HOST "$@" ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
