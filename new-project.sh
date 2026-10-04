#!/bin/zsh
# ボードのひな形から新しいプロジェクトを作る。
#
#   new-project.sh pynq-z1 ~/claude/my-circuit
#
# boards/<board>/template/ を丸ごと写し、ボードの PS7 設定（ps7.tcl）を hw/ に置く。
# できたプロジェクトは fpga-mac が無くても Vivado さえあれば作り直せる（自己完結）。
# 写したあとの改変は自由。fpga-mac 側の更新は自動では入らない。

board=$1 dest=$2
here=${0:A:h}
[[ -n $board && -n $dest ]] || { sed -n '2,8p' "$0"; exit 1 }
[[ -d $here/boards/$board/template ]] || { echo "no template for board '$board'. Boards: ${(j:, :)${(f)$(ls $here/boards)}}" >&2; exit 1 }
[[ -e $dest ]] && { echo "$dest already exists" >&2; exit 1 }

cp -R $here/boards/$board/template $dest
cp $here/boards/$board/ps7.tcl $dest/hw/
git -C $dest init -q 2>/dev/null   # vivado.sh は git のてっぺんをコンテナに載せる
echo "created $dest from boards/$board/template"
echo "next: cd $dest/hw && $here/vivado.sh start && $here/vivado.sh sh 'sim/run.sh'"
