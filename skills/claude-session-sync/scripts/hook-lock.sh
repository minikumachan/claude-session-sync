#!/usr/bin/env bash
#  claude-session-sync : SessionStart/SessionEnd 用ロックフック (macOS / Linux)
#  引数: acquire | release  ／ stdin にフック入力(JSON: cwd, session_id)
set -uo pipefail
ACTION="${1:-}"
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || exit 0
get(){ grep -E "^$1=" "$CFG" 2>/dev/null | head -n1 | cut -d= -f2-; }
SHARE="$(get share)"; [[ -n "$SHARE" ]] || exit 0
SCOPE="$(get lockScope)"; [[ -z "$SCOPE" ]] && SCOPE=project

IN="$(cat 2>/dev/null || true)"
extract(){ printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }
CWD="$(extract cwd)"; [[ -z "$CWD" ]] && CWD="$(pwd)"
SID="$(extract session_id)"

LOCKDIR="$SHARE/locks"; mkdir -p "$LOCKDIR"
if [[ "$SCOPE" == "global" ]]; then KEY="ACTIVE"; else KEY="$(printf '%s' "$CWD" | sed 's/[^A-Za-z0-9]/-/g')"; fi
LOCK="$LOCKDIR/$KEY.lock"
lock_sid(){ [[ -f "$LOCK" ]] && sed -n 's/.*session=\([^ ]*\).*/\1/p' "$LOCK" | head -n1; }

if [[ "$ACTION" == "release" ]]; then
  [[ -f "$LOCK" && "$(lock_sid)" == "$SID" ]] && rm -f "$LOCK"
  exit 0
fi
# acquire
if [[ -f "$LOCK" ]]; then
  OWNER="$(lock_sid)"
  if [[ -n "$OWNER" && "$OWNER" != "$SID" ]]; then
    echo "[claude-session-sync] WARNING: このプロジェクトは別セッション/別デバイスで使用中の可能性 -> $(cat "$LOCK") ／ 同時編集は履歴破損の恐れ。もう一方を終了してください。"
    exit 0
  fi
fi
echo "machine=$(hostname) user=$USER session=$SID scope=$SCOPE key=$KEY start=$(date -u +%FT%TZ)" > "$LOCK"
exit 0
