#!/bin/bash
# 把本目录作为一个 skill（mac2win-remote）以符号链接方式安装到 ~/.claude/skills/，已存在时覆盖更新。
# 用法：./install.sh            安装或覆盖更新
#       ./install.sh --dry-run  只打印将要做的事
# 覆盖规则：
#   不存在                 → 新建链接
#   已是指向本目录的链接   → 无需改动
#   指向别处的链接         → 替换为指向本目录；原链接指向的内容原样保留，只是不再被使用
#                            （例如技能管理工具复制出来的副本）
#   真实目录或文件         → 先移到 ~/.claude/skills-backup/<名称>.<时间戳> 备份，再新建链接
#                            （备份不放在 skills/ 里，避免被当成重名 skill 加载）
# 链接到仓库后，修改仓库里的 SKILL.md 立即生效，不会再出现"仓库与已安装副本不一致"。
# 本脚本只安装技能说明；wr / wsh / wshot 与 Windows 端脚本的安装见"mac2win-remote搭建教程.md"第四步。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"
NAME="mac2win-remote"
TARGET="$DEST/$NAME"
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "未知参数：$1（可用：--dry-run）" >&2; exit 2 ;;
esac

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

[ -f "$HERE/SKILL.md" ] || { echo "本目录缺少 SKILL.md：$HERE" >&2; exit 1; }
run mkdir -p "$DEST"

if [ -L "$TARGET" ]; then
  CURRENT="$(readlink "$TARGET")"
  if [ "$CURRENT" = "$HERE" ]; then
    echo "已是最新：$TARGET -> $HERE"; exit 0
  fi
  echo "覆盖更新：$TARGET 原指向 ${CURRENT}，改为指向 $HERE"
  echo "提示：原位置的内容保留未动；若原链接由技能管理工具维护，它之后重新同步时可能把链接改回去，届时重跑本脚本即可。"
  run rm "$TARGET"
elif [ -e "$TARGET" ]; then
  BACKUP="$HOME/.claude/skills-backup/$NAME.$(date +%Y%m%d%H%M%S)"
  echo "覆盖更新：$TARGET 是真实目录或文件，先备份到 $BACKUP"
  run mkdir -p "$(dirname "$BACKUP")"
  run mv "$TARGET" "$BACKUP"
else
  echo "安装：$TARGET -> $HERE"
fi

run ln -s "$HERE" "$TARGET"
[ "$DRY_RUN" = 1 ] || echo "完成：$NAME 已链接到 $HERE"
