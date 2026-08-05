#!/usr/bin/env bash
# 打一个能拷到 Windows 上装的 zip。
#
#   ./pack.sh              -> dist/ChordAssist-<版本>.zip
#   ./pack.sh --out DIR    换个输出目录
#
# zip 解出来长这样：
#   ChordAssist/           整个丢进 MuseScore 的 Plugins 目录
#   install.bat            双击就装
#   uninstall.bat
#   deploy-windows.ps1     install.bat 调的就是它，也可以自己带参数跑
#   怎么装.txt

set -eu

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SRC/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不认识的参数: $1" >&2; exit 1 ;;
    esac
done

VER="$(sed -n 's/^[[:space:]]*version:[[:space:]]*"\([^"]*\)".*/\1/p' "$SRC/ChordAssist.qml" | head -1)"
[ -n "$VER" ] || VER="0"

NAME="ChordAssist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# --- 插件本体 ---------------------------------------------------------------
mkdir -p "$STAGE/$NAME/core"
cp "$SRC"/ChordAssist.qml "$SRC"/Probe.qml "$STAGE/$NAME/"
cp "$SRC"/core/*.js "$STAGE/$NAME/core/"

# --- Windows 侧的脚本和说明 -------------------------------------------------
# PowerShell 5.1 读没有 BOM 的文件会按 ANSI 解，中文会变乱码，所以加 BOM。
# .bat 保持纯 ASCII，避开控制台代码页的坑。三个都转 CRLF。
crlf_bom() { printf '\xEF\xBB\xBF' > "$2"; sed 's/$/\r/' "$1" >> "$2"; }
crlf()     { sed 's/$/\r/' "$1" > "$2"; }

crlf_bom "$SRC/deploy-windows.ps1" "$STAGE/deploy-windows.ps1"
crlf_bom "$SRC/win/怎么装.txt"      "$STAGE/怎么装.txt"
crlf     "$SRC/win/install.bat"    "$STAGE/install.bat"
crlf     "$SRC/win/uninstall.bat"  "$STAGE/uninstall.bat"

# --- 打包 -------------------------------------------------------------------
mkdir -p "$OUT"
ZIP="$OUT/$NAME-$VER.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -q -r -X "$ZIP" . )

SIZE="$(du -h "$ZIP" | cut -f1)"
echo "打好了: $ZIP  ($SIZE)"
echo
unzip -l "$ZIP" | sed -n '4,$p' | head -20
echo

# --- 怎么拿到 Windows 上去 ---------------------------------------------------
HOST="$(echo "${SSH_CONNECTION:-}" | awk '{print $3}')"
[ -n "$HOST" ] || HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$HOST" ] || HOST="<这台机器的地址>"

cat <<EOF
拷到 Windows：在 Windows 的 PowerShell 里跑

  scp $(whoami)@$HOST:"$ZIP" \$env:USERPROFILE\\Downloads\\

然后到 下载 文件夹里，右键 → 全部解压缩 → 双击 install.bat → 重启 MuseScore。
EOF
