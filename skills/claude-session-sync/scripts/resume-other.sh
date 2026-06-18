#!/usr/bin/env bash
#  claude-session-sync : 別デバイスの会話を取り込んで続きから再開可能にする (macOS / Linux)
set -euo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup.sh を実行してください。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2-; }
encode(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

SHARE="$(get share)"
SHARE_PROJECTS="$SHARE/sessions/projects"
LOCAL_PROJECTS="$CLAUDE/projects"

if [[ "${1:-}" == "-l" || "${1:-}" == "--list" || -z "${1:-}" ]]; then
  echo "=== 共有内の会話セッション(新しい順・最大40件) ==="
  find "$SHARE_PROJECTS" -name '*.jsonl' 2>/dev/null \
    | grep -Ev '/subagents/|/wf_|/agent-[^/]*\.jsonl$|/journal\.jsonl$' \
    | tr '\n' '\0' | xargs -0 ls -lt 2>/dev/null | head -n 40 \
    | awk '{ n=$NF; sub(/.*\//,"",n); sub(/\.jsonl$/,"",n); print $6, $7, $8, n }'
  echo
  echo "取り込み: resume-other.sh <session-id> [作業フォルダ]"
  exit 0
fi

SID="$1"; TARGET="${2:-$(pwd)}"
SRC="$(find "$SHARE_PROJECTS" -name "$SID.jsonl" 2>/dev/null | head -n1 || true)"
[[ -n "$SRC" ]] || { echo "セッション $SID が共有内に見つかりません。-l で確認してください。" >&2; exit 1; }
FULL="$(cd "$TARGET" && pwd)"
DEST_DIR="$LOCAL_PROJECTS/$(encode "$FULL")"
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/$SID.jsonl"
[[ -f "$DEST" ]] && cp "$DEST" "$DEST.bak_$(date +%Y%m%d_%H%M%S)"
cp "$SRC" "$DEST"
echo "取り込み完了 → $DEST"
echo "続きから再開:"
echo "  cd \"$FULL\""
echo "  claude --resume $SID"
echo "※ 対象フォルダに実プロジェクトのファイルが必要です。"
