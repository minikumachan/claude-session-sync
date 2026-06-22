#!/usr/bin/env bash
#  claude-session-sync : ロックフック (macOS / Linux)
#  引数: acquire(SessionStart)| release(SessionEnd)| beat(UserPromptSubmit=実行中ハートビート)
#  stdin にフック入力(JSON: cwd, session_id)。同機 or 失効(lockTakeoverSec 超)ロックは奪取、別機で新鮮なら保護。
set -uo pipefail
[[ -n "${CSS_TITLEGEN:-}" ]] && exit 0   # 自動タイトル生成中の claude -p はロック対象外
ACTION="${1:-}"
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || exit 0
get(){ grep -E "^$1=" "$CFG" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r'; }
SHARE="$(get share)"; [[ -n "$SHARE" ]] || exit 0
SCOPE="$(get lockScope)"; [[ -z "$SCOPE" ]] && SCOPE=project

IN="$(cat 2>/dev/null || true)"
extract(){ printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }
CWD="$(extract cwd)"; [[ -z "$CWD" ]] && CWD="$(pwd)"
SID="$(extract session_id)"

LOCKDIR="$SHARE/locks"; mkdir -p "$LOCKDIR"
if [[ "$SCOPE" == "global" ]]; then KEY="ACTIVE"; else KEY="$(printf '%s' "$CWD" | sed 's/[^A-Za-z0-9]/-/g')"; fi
LOCK="$LOCKDIR/$KEY.lock"
TAKEOVER="$(get lockTakeoverSec)"; [[ "$TAKEOVER" =~ ^[0-9]+$ ]] || TAKEOVER=1800   # 別機ロックを失効とみなす秒(既定30分)
lock_sid(){ [[ -f "$LOCK" ]] && sed -n 's/.*session=\([^ ]*\).*/\1/p' "$LOCK" | head -n1; }
lock_machine(){ [[ -f "$LOCK" ]] && sed -n 's/.*machine=\([^ ]*\).*/\1/p' "$LOCK" | head -n1; }
lock_age(){ [[ -f "$LOCK" ]] || { echo 999999; return; }; local now mt; now=$(date +%s); mt=$(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0); echo $((now-mt)); }
write_lock(){ echo "machine=$(hostname) user=$USER session=$SID scope=$SCOPE key=$KEY start=$(date -u +%FT%TZ)" > "$LOCK"; }
# 現在セッションで奪取してよいか: 自分の所有 / ロック無し / 同機 / 別機でも失効(takeoverSec 超)なら 0。別機で新鮮なら 1(保護)。
can_take(){ [[ -f "$LOCK" ]] || return 0; local o; o="$(lock_sid)"; { [[ -z "$o" || "$o" == "$SID" ]]; } && return 0; [[ "$(lock_machine)" == "$(hostname)" ]] && return 0; [[ "$(lock_age)" -gt "$TAKEOVER" ]] && return 0; return 1; }

if [[ "$ACTION" == "release" ]]; then
  [[ -f "$LOCK" && "$(lock_sid)" == "$SID" ]] && rm -f "$LOCK"
  exit 0
fi
if [[ "$ACTION" == "beat" ]]; then
  [[ -n "$SID" ]] && can_take && write_lock
  exit 0
fi
# acquire
if ! can_take; then
  echo "[claude-session-sync] WARNING: このプロジェクトは別デバイスで使用中の可能性 -> $(cat "$LOCK") ／ 同時編集は履歴破損の恐れ。もう一方を終了してください。"
  exit 0
fi
write_lock
# デバイスタグ(同機種識別用): sessionId -> deviceName を devices.map に一度だけ記録
if [[ -n "$SID" ]]; then
  DEV="$(get deviceName)"; [[ -z "$DEV" ]] && DEV="$(hostname)"
  DM="$SHARE/sessions/devices.map"; mkdir -p "$SHARE/sessions"
  found=0; [[ -f "$DM" ]] && awk -F'\t' -v s="$SID" 'BEGIN{e=1}$1==s{e=0}END{exit e}' "$DM" && found=1
  [[ $found -eq 0 ]] && printf '%s\t%s\n' "$SID" "$DEV" >> "$DM"
fi
exit 0
