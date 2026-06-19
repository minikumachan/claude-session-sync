#!/usr/bin/env bash
#  claude-session-sync : PC ログイン時の自動起動ランチャー (macOS / Linux)
#    config: bootLaunch(off|new|last|<sid>) / bootRemote(true|false|ask) / bootCheckMulti(true|false)
#    install-autostart.sh で LaunchAgent(.plist) / autostart(.desktop) として登録される。
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "session-sync 未設定です。先に setup を実行してください。"; sleep 3; exit 0; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
cwd_of(){ head -n1 "$1" 2>/dev/null | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p'; }

BL="$(get bootLaunch)"; [[ -z "$BL" ]] && BL=off
[[ "$BL" == "off" ]] && exit 0
BR="$(get bootRemote)"; [[ -z "$BR" ]] && BR=false
CM="$(get bootCheckMulti)"; [[ -z "$CM" ]] && CM=true
command -v claude >/dev/null 2>&1 || { echo "⛔ claude が見つかりません。"; sleep 5; exit 1; }
SHARE="$(get share)"; HOSTN="$(hostname)"; PJ="$CLAUDE/projects"

# --- 多重起動チェック(他デバイスが共有ロック保持中か / 12h 以内のもののみ) ---
if [[ "$CM" != "false" && -n "$SHARE" && -d "$SHARE/locks" ]]; then
  others=""
  while IFS= read -r lf; do
    [[ -f "$lf" ]] || continue
    [[ -n "$(find "$lf" -mmin -720 2>/dev/null)" ]] || continue
    m="$(grep -oE 'machine=[^ ]+' "$lf" 2>/dev/null | head -n1 | cut -d= -f2)"
    [[ -n "$m" && "$m" != "$HOSTN" ]] && others+="   $(tr -d '\n' < "$lf")"$'\n'
  done < <(find "$SHARE/locks" -name '*.lock' 2>/dev/null)
  if [[ -n "$others" ]]; then
    echo "⛔ 別デバイスで Claude が使用中の可能性(同時起動は履歴破損 .sync-conflict の恐れ):"
    printf '%s' "$others"
    echo "自動起動を中止しました。もう一方を終了してから手動で起動してください。"; sleep 6; exit 0
  fi
fi

# --- どの会話で開くか ---
ARGS=(); sid=""; cwd=""
if [[ "$BL" == "last" ]]; then
  f="$(ls -1t "$PJ"/*/*.jsonl 2>/dev/null | head -n1)"
  if [[ -n "$f" ]]; then sid="$(basename "$f" .jsonl)"; cwd="$(cwd_of "$f")"; fi
elif [[ "$BL" != "new" ]]; then
  sid="$BL"; f="$(find "$PJ" -name "$sid.jsonl" 2>/dev/null | head -n1)"
  [[ -n "$f" ]] && cwd="$(cwd_of "$f")"
fi
[[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd"
[[ -n "$sid" ]] && ARGS+=(--resume "$sid")

# --- Remote Control(スマホ/claude.ai から操作) ---
use_remote=0
case "$BR" in
  true) use_remote=1;;
  ask)  echo "リモート操作(スマホ/claude.ai から操作)を有効にしますか? [y/N] (8秒で N)"
        read -r -t 8 ans || ans=""; [[ "$ans" =~ ^[yY]$ ]] && use_remote=1;;
esac
[[ $use_remote -eq 1 ]] && ARGS+=(--remote-control)

echo "▶ claude ${ARGS[*]:-}"
exec command claude "${ARGS[@]}"
