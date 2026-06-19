#!/usr/bin/env bash
#  claude-session-sync : デバイス切替検知 + 同期/移行の健全性チェック + 起動オプション記録 (macOS / Linux / SessionStart)
#    1) lastseen.map で別デバイス再開を検知し、対応作業パス(検証済)+同期/移行の健全性を stdout で Claude に通知。
#    2) 起動オプション(model/effort/permission)を launchopts.map に記録(再開時の引き継ぎ用)。
#       env CSS_LAUNCH_MODEL/EFFORT/PERM 優先、無ければ stdin の model と既存値を保持。
#    conf の deviceSwitchNotice=false で 1) の通知のみ無効化(記録は継続)。
set -uo pipefail
[ -n "${CSS_TITLEGEN:-}" ] && exit 0
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[ -f "$CFG" ] || exit 0
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
NOTICE=1; [ "$(get deviceSwitchNotice)" = "false" ] && NOTICE=0

raw="$(cat)"
sid="$(printf '%s' "$raw" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
cwd="$(printf '%s' "$raw" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
smodel="$(printf '%s' "$raw" | sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[ -z "$cwd" ] && cwd="$(pwd)"
[ -z "$sid" ] && exit 0

dev="$(get deviceName)"; [ -z "$dev" ] && dev="$(hostname)"
SHARE="$(get share)"
mapdir="$CLAUDE/sessions"; [ -n "$SHARE" ] && mapdir="$SHARE/sessions"
mkdir -p "$mapdir"; lastseen="$mapdir/lastseen.map"; launchmap="$mapdir/launchopts.map"

lock(){ local d="$1.lockd" i=0; while ! mkdir "$d" 2>/dev/null; do i=$((i+1)); [ $i -gt 30 ] && break; sleep 0.03; done; }
unlock(){ rmdir "$1.lockd" 2>/dev/null || true; }
map_field(){ grep -F "$1"$'\t' "$2" 2>/dev/null | tail -n1 | cut -f"$3"; }   # key file fieldno
map_set(){ local file="$1" key="$2"; shift 2; lock "$file"; local tmp; tmp="$(mktemp)"
  [ -f "$file" ] && grep -vF "$key"$'\t' "$file" 2>/dev/null > "$tmp" || true
  { printf '%s' "$key"; for f in "$@"; do printf '\t%s' "$f"; done; printf '\n'; } >> "$tmp"
  mv "$tmp" "$file"; unlock "$file"; }

# ---- 1) 起動オプションの記録(env 優先・無ければ既存保持) ----
pModel="$(map_field "$sid" "$launchmap" 2)"; pEff="$(map_field "$sid" "$launchmap" 3)"; pPerm="$(map_field "$sid" "$launchmap" 4)"
nModel="${CSS_LAUNCH_MODEL:-}"; [ -z "$nModel" ] && nModel="${smodel:-$pModel}"
nEff="${CSS_LAUNCH_EFFORT:-}"; [ -z "$nEff" ] && nEff="$pEff"
nPerm="${CSS_LAUNCH_PERM:-}"; [ -z "$nPerm" ] && nPerm="$pPerm"
map_set "$launchmap" "$sid" "$nModel" "$nEff" "$nPerm" "$(date -u +%FT%TZ)"

# ---- 2) デバイス切替の検知・通知(+同期/移行の健全性) ----
if [ "$NOTICE" = "1" ]; then
  translate(){ local p="$1" rel=""
    [ -z "$p" ] && return
    [ -d "$p" ] && { printf '%s' "$p"; return; }
    case "$p" in
      [A-Za-z]:\\Users\\*) rel="$(printf '%s' "$p" | sed -E 's#^[A-Za-z]:\\Users\\[^\\]+\\##; s#\\#/#g')";;
      /Users/*) rel="$(printf '%s' "$p" | sed -E 's#^/Users/[^/]+/##')";;
      /home/*)  rel="$(printf '%s' "$p" | sed -E 's#^/home/[^/]+/##')";;
    esac
    [ -z "$rel" ] && return
    [ -d "$HOME/$rel" ] && printf '%s' "$HOME/$rel"
  }
  sync_health(){ local work="$1" out=""
    if [ -n "$SHARE" ] && [ ! -d "$SHARE" ]; then printf '%s' "⚠ 共有フォルダ未到達($SHARE): 同期停止/未マウントの可能性。最新でない恐れ"; return; fi
    local sf; sf="$(find "$CLAUDE/projects" -name "$sid.jsonl" 2>/dev/null | head -n1)"
    if [ -n "$sf" ]; then
      if ls "$(dirname "$sf")" 2>/dev/null | grep -q 'sync-conflict'; then out="$out⚠ 履歴フォルダに同期競合ファイルあり: 履歴破損の恐れ。解決まで同一プロジェクト編集を控える / "; fi
    else out="$out⚠ この会話の履歴(.jsonl)が未到達の可能性(同期未完了?) / "; fi
    if [ -n "$work" ] && [ -d "$work" ]; then
      if ls "$work" 2>/dev/null | grep -qE 'sync-conflict|^~syncthing~|^\.syncthing\.'; then out="$out⚠ 作業フォルダに同期競合/転送中ファイルあり: 同期完了を待つ / "; fi
    fi
    printf '%s' "$out"
  }
  prevdev="$(map_field "$sid" "$lastseen" 2)"; prevcwd="$(map_field "$sid" "$lastseen" 3)"
  if [ -n "$prevdev" ] && [ "$prevdev" != "$dev" ]; then
    sug="$(translate "$prevcwd")"
    health="$(sync_health "$sug")"
    msg="[claude-session-sync] デバイス切替を検知。前回『$prevdev』(作業フォルダ: $prevcwd) → 現在『$dev』。"
    if [ -n "$sug" ]; then msg="$msg このデバイスでの対応作業フォルダ(検証済): 『$sug』。以降はこのデバイスの絶対パスを使う(必要なら cd \"$sug\")。"
    else msg="$msg 対応作業フォルダを自動特定できず(現在地: $cwd)。このデバイスの絶対パスで作業する。"; fi
    if [ -n "$health" ]; then msg="$msg 【同期/移行の注意】 $health— 解消まで重複作業や誤編集を避ける。"
    else msg="$msg 同期/移行: 問題は検出されず(履歴・作業フォルダとも到達済・競合なし)。"; fi
    printf '%s\n' "$msg"
  fi
  map_set "$lastseen" "$sid" "$dev" "$cwd" "$(date -u +%FT%TZ)"
fi
exit 0
