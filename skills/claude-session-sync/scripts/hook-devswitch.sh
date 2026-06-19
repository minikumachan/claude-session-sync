#!/usr/bin/env bash
#  claude-session-sync : デバイス切替検知フック (macOS / Linux / SessionStart)
#    会話が前回と異なるデバイスで開始/再開されたら、その旨と「このデバイスでの適切な作業パス」を
#    stdout に出力して Claude の文脈へ伝える。sid -> device|cwd|time を lastseen.map に記録。
#    conf の deviceSwitchNotice=false で無効化。
set -uo pipefail
[ -n "${CSS_TITLEGEN:-}" ] && exit 0
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[ -f "$CFG" ] || exit 0
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
[ "$(get deviceSwitchNotice)" = "false" ] && exit 0

raw="$(cat)"
sid="$(printf '%s' "$raw" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
cwd="$(printf '%s' "$raw" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[ -z "$cwd" ] && cwd="$(pwd)"
[ -z "$sid" ] && exit 0

dev="$(get deviceName)"; [ -z "$dev" ] && dev="$(hostname)"
SHARE="$(get share)"
mapdir="$CLAUDE/sessions"; [ -n "$SHARE" ] && mapdir="$SHARE/sessions"
mkdir -p "$mapdir"; mapfile="$mapdir/lastseen.map"

translate(){  # $1=prevcwd -> echo local path(あれば)
  local p="$1" rel=""
  [ -z "$p" ] && return
  [ -d "$p" ] && { printf '%s' "$p"; return; }
  case "$p" in
    [A-Za-z]:\\Users\\*) rel="$(printf '%s' "$p" | sed -E 's#^[A-Za-z]:\\Users\\[^\\]+\\##; s#\\#/#g')";;
    /Users/*) rel="$(printf '%s' "$p" | sed -E 's#^/Users/[^/]+/##')";;
    /home/*)  rel="$(printf '%s' "$p" | sed -E 's#^/home/[^/]+/##')";;
  esac
  [ -z "$rel" ] && return
  local cand="$HOME/$rel"
  [ -d "$cand" ] && printf '%s' "$cand"
}

prevdev=""; prevcwd=""
if [ -f "$mapfile" ]; then
  line="$(grep -F "$sid"$'\t' "$mapfile" 2>/dev/null | tail -n1)"
  if [ -n "$line" ]; then prevdev="$(printf '%s' "$line" | cut -f2)"; prevcwd="$(printf '%s' "$line" | cut -f3)"; fi
fi

if [ -n "$prevdev" ] && [ "$prevdev" != "$dev" ]; then
  sug="$(translate "$prevcwd")"
  msg="[claude-session-sync] デバイス切替を検知しました。この会話は前回『$prevdev』(作業フォルダ: $prevcwd)で使われ、現在は『$dev』です。"
  if [ -n "$sug" ]; then msg="$msg このデバイスでの対応する作業フォルダは『$sug』です。以降のファイル操作はこのデバイスのパスを使ってください(必要なら cd \"$sug\")。"
  else msg="$msg 対応する作業フォルダを自動特定できませんでした(現在地: $cwd)。このデバイスの絶対パスで作業し、別デバイスのパス表記はそのまま使わないでください。"; fi
  printf '%s\n' "$msg"
fi

tmp="$(mktemp)"
if [ -f "$mapfile" ]; then grep -vF "$sid"$'\t' "$mapfile" 2>/dev/null > "$tmp" || true; fi
printf '%s\t%s\t%s\t%s\n' "$sid" "$dev" "$cwd" "$(date -u +%FT%TZ)" >> "$tmp"
mv "$tmp" "$mapfile"
exit 0
