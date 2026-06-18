#!/usr/bin/env bash
#  claude-session-sync : Stop フック = 会話タイトルの自動更新 (macOS / Linux)
#  Claude が応答を終えるたびに呼ばれ、一定ターンごとに title-gen.sh を
#  バックグラウンド起動して会話内容に合うタイトルへ改名する。フックは即終了。
set -uo pipefail
[[ -n "${CSS_TITLEGEN:-}" ]] && exit 0   # title-gen 経由の claude -p からの再入を無視

CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$CFG" ]] || exit 0
get(){ grep -E "^$1=" "$CFG" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r'; }
[[ "$(get autoTitle)" == "false" ]] && exit 0
EVERY="$(get titleEvery)"; [[ "$EVERY" =~ ^[0-9]+$ ]] || EVERY=5; [[ "$EVERY" -lt 1 ]] && EVERY=1

IN="$(cat 2>/dev/null || true)"
extract(){ printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }
SID="$(extract session_id)"; TP="$(extract transcript_path)"
[[ -n "$SID" && -n "$TP" && -f "$TP" ]] || exit 0

# ユーザー発話数を概算(上限つき)
USERMSGS="$(head -n 800 "$TP" 2>/dev/null | grep -c '"type":"user"' || true)"
[[ "$USERMSGS" =~ ^[0-9]+$ ]] || USERMSGS=0
[[ "$USERMSGS" -lt 2 ]] && exit 0

STATEDIR="$CLAUDE/.session-sync/title-state"; mkdir -p "$STATEDIR"
STATE="$STATEDIR/$SID.cnt"
LAST=0; [[ -f "$STATE" ]] && LAST="$(tr -dc '0-9' < "$STATE" 2>/dev/null || echo 0)"; [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
if [[ "$LAST" -ne 0 && $((USERMSGS-LAST)) -lt "$EVERY" ]]; then exit 0; fi
echo "$USERMSGS" > "$STATE"   # 二重起動防止のため先に記録

nohup bash "$DIR/title-gen.sh" --sid "$SID" --transcript "$TP" >/dev/null 2>&1 &
exit 0
