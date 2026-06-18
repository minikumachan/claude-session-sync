#!/usr/bin/env bash
#  claude-session-sync : ロック付きで Claude を起動 (macOS / Linux)
set -euo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup.sh --share '<.../_ClaudeCode>' を実行してください。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2-; }
encode(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

SHARE="$(get share)"; [[ -n "$SHARE" ]] || { echo "config に share がありません。" >&2; exit 1; }
SCOPE="$(get lockScope)"; [[ -z "$SCOPE" ]] && SCOPE=project
LOCKDIR="$SHARE/locks"; mkdir -p "$LOCKDIR"
KEY="ACTIVE"; [[ "$SCOPE" == "project" ]] && KEY="$(encode "$(pwd)")"
LOCK="$LOCKDIR/$KEY.lock"

FORCE=0; UNLOCK=0; ARGS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --force) FORCE=1; shift;;
  --unlock) UNLOCK=1; shift;;
  *) ARGS+=("$1"); shift;;
esac; done

if [[ $UNLOCK -eq 1 ]]; then
  if [[ -f "$LOCK" ]]; then rm -f "$LOCK"; echo "🔓 解除: $KEY"; else echo "ロックなし: $KEY"; fi; exit 0
fi
if [[ -f "$LOCK" && $FORCE -eq 0 ]]; then
  echo "⛔ このプロジェクト/セッションは使用中の可能性: $(cat "$LOCK")" >&2
  echo "   解決: もう一方で終了 / 残骸なら --force / 強制解除は cc.sh --unlock" >&2
  exit 1
fi
echo "machine=$(hostname) user=$USER pid=$$ scope=$SCOPE key=$KEY start=$(date -u +%FT%TZ)" > "$LOCK"
echo "🔒 lock: $KEY"
cleanup(){ if [[ -f "$LOCK" ]] && grep -q "pid=$$\b" "$LOCK"; then rm -f "$LOCK"; echo "🔓 unlock: $KEY"; fi; }
trap cleanup EXIT
claude "${ARGS[@]}"
