#!/usr/bin/env bash
#  claude-session-sync : 起動ショートカット launcher (macOS / Linux)
#  Mode: c=通常起動(現在地) / cfp=固定パス起動 / ch=履歴UI / ca=設定。
#  conf(session-sync.local.conf)の launchPath / remoteC / remoteCfp を読む。
#  c・cfp は設定でリモートコントロールが ON(既定)なら --remote-control を付与。余分な引数は claude へ素通し。
set -uo pipefail
MODE="${1:-c}"; shift 2>/dev/null || true
CLAUDE="$HOME/.claude"; SCRIPTS="$CLAUDE/skills/claude-session-sync/scripts"; CFG="$CLAUDE/session-sync.local.conf"
get(){ [ -f "$CFG" ] && grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r' || true; }

case "$MODE" in
  ch) exec bash "$SCRIPTS/history-ui.sh" ;;
  ca) exec bash "$SCRIPTS/autostart-ui.sh" ;;
esac

# 実体 claude(css-bin の shim を除外して PATH から解決)
self="$HOME/.claude/css-bin"; real=""
oldifs="$IFS"; IFS=:
for d in $PATH; do
  [ "$d" = "$self" ] && continue
  if [ -f "$d/claude" ] && [ -x "$d/claude" ]; then real="$d/claude"; break; fi
done
IFS="$oldifs"
[ -n "$real" ] || { echo "real claude が見つかりません(npm 等で導入してください)。" >&2; exit 1; }

cargs=()
if [ "$MODE" = "cfp" ]; then
  lp="$(get launchPath)"
  if [ -n "$lp" ] && [ -d "$lp" ]; then cd "$lp" || true
  else echo "固定パス(cfp)が未設定/不在です。『claude -a』→ 起動ショートカット設定 で設定してください。" >&2; fi
  [ "$(get remoteCfp)" != "off" ] && cargs+=(--remote-control)   # 既定 ON
else
  [ "$(get remoteC)" != "off" ] && cargs+=(--remote-control)     # 既定 ON
fi
# 空配列でも set -u で落ちないように展開(macOS の古い bash 3.2 対応)
exec "$real" ${cargs[@]+"${cargs[@]}"} "$@"
