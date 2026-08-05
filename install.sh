#!/usr/bin/env bash
# 把和弦助手装进 MuseScore。
#
#   ./install.sh              自动找 MuseScore 目录并复制
#   ./install.sh --link       改成建软链（改完代码不用重装，但个别版本不跟软链）
#   ./install.sh --dir PATH   指定目标目录
#   ./install.sh --list       只列出找到的候选目录，不动手
#
# 装完在 MuseScore 里：Home → Plugins 找到「和弦助手」启用，
# 然后从 菜单 → Plugins 调用。

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="ChordAssist"

MODE="copy"
FORCE_DIR=""
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --link) MODE="link"; shift ;;
        --dir)  FORCE_DIR="${2:-}"; shift 2 ;;
        --list) LIST_ONLY=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不认识的参数: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# 找候选目录
# ---------------------------------------------------------------------------

DOCS="$HOME/Documents"
if command -v xdg-user-dir >/dev/null 2>&1; then
    D="$(xdg-user-dir DOCUMENTS 2>/dev/null)"
    # 没配 XDG 时 xdg-user-dir 会把 $HOME 原样吐回来，那种情况不能用
    if [ -n "$D" ] && [ "$D" != "$HOME" ]; then DOCS="$D"; fi
fi

# 只往 Plugins 目录装。这个插件是 apiversion 1（老的 MuseScore {} 写法），
# 而 MuseScore 只有扫 Plugins 目录时才会把插件标成 legacy 并用 v1 引擎跑它；
# 新的 extensions 目录（放 manifest.json 的那个）走 v2 通道，v1 插件放进去不会动。
CANDIDATES=(
    "$DOCS/MuseScore4/Plugins"
    "$DOCS/MuseScore4Development/Plugins"
    "$DOCS/MuseScore5/Plugins"
    "$DOCS/MuseScore5Development/Plugins"
    # Flatpak 装的
    "$HOME/.var/app/org.musescore.MuseScore/data/MuseScore4/Plugins"
    "$HOME/.var/app/org.musescore.MuseScore/Documents/MuseScore4/Plugins"
)

FOUND=()
for d in "${CANDIDATES[@]}"; do
    if [ -d "$d" ]; then FOUND+=("$d"); fi
done

if [ "$LIST_ONLY" = "1" ]; then
    echo "候选目录（存在的打 ✓）："
    for d in "${CANDIDATES[@]}"; do
        if [ -d "$d" ]; then echo "  ✓ $d"; else echo "    $d"; fi
    done
    exit 0
fi

TARGETS=()
if [ -n "$FORCE_DIR" ]; then
    TARGETS=("$FORCE_DIR")
elif [ ${#FOUND[@]} -gt 0 ]; then
    TARGETS=("${FOUND[@]}")
else
    cat <<EOF
没找到 MuseScore 的插件目录。可能是还没装 MuseScore，或者从没启动过它
（这些目录是第一次运行时才创建的）。

三个办法：
  1. 先装并启动一次 MuseScore，再跑这个脚本
  2. 手动指定：./install.sh --dir "\$HOME/Documents/MuseScore4/Plugins"
  3. 让脚本建目录：mkdir -p "\$HOME/Documents/MuseScore4/Plugins" 后重跑

已经查过这些位置：
EOF
    for d in "${CANDIDATES[@]}"; do echo "  $d"; done
    exit 1
fi

# ---------------------------------------------------------------------------
# 安装
# ---------------------------------------------------------------------------

install_to() {
    local base="$1"
    local dest="$base/$NAME"

    mkdir -p "$base" || { echo "  建不了目录 $base"; return 1; }

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "  已存在，先移除旧的: $dest"
        rm -rf "$dest"
    fi

    if [ "$MODE" = "link" ]; then
        ln -s "$SRC" "$dest" || return 1
        echo "  软链 → $dest"
    else
        mkdir -p "$dest/core"
        cp "$SRC"/*.qml     "$dest/"      2>/dev/null
        cp "$SRC"/core/*.js "$dest/core/" 2>/dev/null
        echo "  复制 → $dest"
    fi
    return 0
}

echo "源目录: $SRC"
echo "方式:   $MODE"
echo

OK=0
for t in "${TARGETS[@]}"; do
    echo "装到 $t"
    if install_to "$t"; then OK=$((OK+1)); fi
    echo
done

if [ "$OK" = "0" ]; then
    echo "一个都没装上。"
    exit 1
fi

cat <<EOF
装好了（$OK 处）。

接下来：
  1. 启动 / 重启 MuseScore
  2. Home → Plugins，找到「和弦助手」和「和弦助手 · 环境探针」，都打勾启用
  3. 打开一份吉他谱，在谱面上选中一个音符
  4. 菜单 → Plugins → 和弦助手 · 环境探针 → 把报告贴回来

卸载：./uninstall.sh
EOF
