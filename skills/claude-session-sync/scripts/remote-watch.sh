#!/usr/bin/env bash
#  claude-session-sync : リモート起動ウォッチャ (macOS / Linux)
#    共有フォルダの trigger(inbox) を監視し、トリガで `claude --remote-control [--resume <sid>]` を起動。
#    install-autostart.sh --watch で LaunchAgent/autostart の常駐として登録。
#    トリガ: スマホから同期フォルダ <share>/remote/inbox に1ファイル置くだけ。
#            新規=任意名(例 wake.trig) / 特定会話=ファイル名か中身に session-id(UUID) を含める。
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || exit 0
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
cwd_of(){ head -n1 "$1" 2>/dev/null | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p'; }

SHARE="$(get share)"; [[ -n "$SHARE" ]] || exit 0
WD="$(get remoteWatchDir)"; [[ -z "$WD" ]] && WD="$SHARE/remote"
INBOX="$WD/inbox"; DONE="$WD/done"; STATUS="$WD/status"; PJ="$CLAUDE/projects"
mkdir -p "$INBOX" "$DONE" "$STATUS"
INTERVAL="$(get remoteWatchInterval)"; [[ -z "$INTERVAL" ]] && INTERVAL=10

# 二重起動防止
LOCK="$WD/watcher.lock"
if ! ( set -o noclobber; printf '%s\n' "machine=$(hostname) pid=$$" > "$LOCK" ) 2>/dev/null; then exit 0; fi
trap 'rm -f "$LOCK"' EXIT

open_term(){  # $1=cwd  残りの引数=claude の引数
  local cwd="$1"; shift
  local cmd="cd \"$cwd\" && command claude $*"
  if [[ "$(uname)" == "Darwin" ]]; then
    osascript -e "tell application \"Terminal\" to do script \"$cmd\"" >/dev/null 2>&1
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -lc "$cmd" >/dev/null 2>&1 &
  elif command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -lc "$cmd" >/dev/null 2>&1 &
  else
    nohup bash -lc "$cmd" >/dev/null 2>&1 &
  fi
}

while true; do
  [[ -f "$WD/stop" ]] && { rm -f "$WD/stop"; break; }
  for t in "$INBOX"/*; do
    [[ -e "$t" ]] || continue
    name="$(basename "$t")"; [[ "$name" == "watcher.lock" ]] && continue
    blob="$name $(cat "$t" 2>/dev/null)"
    sid="$(printf '%s' "$blob" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1)"
    cwd="$HOME"; args=(--remote-control)
    if [[ -n "$sid" ]]; then
      f="$(find "$PJ" -name "$sid.jsonl" 2>/dev/null | head -n1)"
      if [[ -n "$f" ]]; then c="$(cwd_of "$f")"; [[ -n "$c" && -d "$c" ]] && cwd="$c"; args=(--resume "$sid" --remote-control); fi
    fi
    if command -v claude >/dev/null 2>&1; then
      open_term "$cwd" "${args[@]}"
      echo "started machine=$(hostname) sid=$sid args=${args[*]} time=$(date -u +%FT%TZ)" > "$STATUS/$name.ack"
    else
      echo "error: claude not found time=$(date -u +%FT%TZ)" > "$STATUS/$name.ack"
    fi
    mv -f "$t" "$DONE/$(date +%Y%m%d_%H%M%S)_$name" 2>/dev/null || rm -f "$t"
  done
  sleep "$INTERVAL"
done
