#!/usr/bin/env bash
# 从 MuseScore 里卸掉和弦助手。
#
#   ./uninstall.sh            自动找并删除
#   ./uninstall.sh --dir PATH 指定目录
#   ./uninstall.sh --dry-run  只看会删什么，不真删

set -u

NAMES=("ChordAssist" "chord-assist")   # 后一个是早期版本用过的目录名
FORCE_DIR=""
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) FORCE_DIR="${2:-}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不认识的参数: $1"; exit 1 ;;
    esac
done

DOCS="$HOME/Documents"
if command -v xdg-user-dir >/dev/null 2>&1; then
    D="$(xdg-user-dir DOCUMENTS 2>/dev/null)"
    # 没配 XDG 时 xdg-user-dir 会把 $HOME 原样吐回来，那种情况不能用
    if [ -n "$D" ] && [ "$D" != "$HOME" ]; then DOCS="$D"; fi
fi

CANDIDATES=(
    "$DOCS/MuseScore4/Plugins"
    "$DOCS/MuseScore4Development/Plugins"
    "$DOCS/MuseScore5/Plugins"
    "$DOCS/MuseScore5Development/Plugins"
    "$HOME/.var/app/org.musescore.MuseScore/data/MuseScore4/Plugins"
    "$HOME/.var/app/org.musescore.MuseScore/Documents/MuseScore4/Plugins"
)

if [ -n "$FORCE_DIR" ]; then
    CANDIDATES=("$FORCE_DIR")
fi

REMOVED=0
for base in "${CANDIDATES[@]}"; do
    for name in "${NAMES[@]}"; do
        dest="$base/$name"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            if [ "$DRY" = "1" ]; then
                echo "会删: $dest"
            else
                rm -rf "$dest"
                echo "已删: $dest"
            fi
            REMOVED=$((REMOVED+1))
        fi
    done
done

if [ "$REMOVED" = "0" ]; then
    echo "没找到已安装的和弦助手。"
    exit 0
fi

if [ "$DRY" = "0" ]; then
    echo
    echo "删完了。MuseScore 里如果还留着菜单项，重启一次就没了。"
    echo "（插件的启用状态记在 MuseScore 自己的配置里，删目录不影响别的插件。）"
fi
