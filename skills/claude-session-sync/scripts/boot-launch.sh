#!/usr/bin/env bash
#  claude-session-sync : PC ログイン時の自動起動ランチャー (macOS / Linux)
#    起動項目は ~/.claude/session-sync.boot.json (配列) に保存。各項目:
#      {type:new|last|resume, sid, model, effort, remote:true|false|"ask"}
#      new はモデル/思考深度(effort)を反映。last/resume は会話のものを使用(付けない)。
#    旧 conf bootLaunch/bootRemote も後方互換で読む。起動前に多重起動チェック。
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"; BJ="$CLAUDE/session-sync.boot.json"
[[ -f "$CFG" ]] || { echo "session-sync 未設定です。"; sleep 3; exit 0; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
cwd_of(){ head -n1 "$1" 2>/dev/null | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p'; }
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

CM="$(get bootCheckMulti)"; [[ -z "$CM" ]] && CM=true
SHARE="$(get share)"; HOSTN="$(hostname)"; PJ="$CLAUDE/projects"
command -v claude >/dev/null 2>&1 || { echo "⛔ claude が見つかりません。"; sleep 5; exit 1; }
PY="$(command -v python3 || command -v python || true)"

# 多重起動チェック(他デバイスの有効ロック<12h)
if [[ "$CM" != "false" && -n "$SHARE" && -d "$SHARE/locks" ]]; then
  others=""
  while IFS= read -r lf; do
    [[ -f "$lf" ]] || continue
    [[ -n "$(find "$lf" -mmin -720 2>/dev/null)" ]] || continue
    m="$(grep -oE 'machine=[^ ]+' "$lf" 2>/dev/null | head -n1 | cut -d= -f2)"
    [[ -n "$m" && "$m" != "$HOSTN" ]] && others+="   $(tr -d '\n' < "$lf")"$'\n'
  done < <(find "$SHARE/locks" -name '*.lock' 2>/dev/null)
  if [[ -n "$others" ]]; then
    echo "⛔ 別デバイスで Claude が使用中の可能性(同時起動は履歴破損の恐れ):"; printf '%s' "$others"
    echo "自動起動を中止しました。"; sleep 6; exit 0
  fi
fi

# 起動項目を TSV(type sid model effort remote)で出力
emit_entries(){
  if [[ -f "$BJ" && -n "$PY" ]]; then
    "$PY" - "$BJ" <<'PYEOF'
import json,sys
try: a=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: a=[]
if isinstance(a,dict): a=[a]
for e in (a or []):
    if not isinstance(e,dict): continue
    r=e.get('remote',False)
    r='ask' if r=='ask' else ('true' if (r is True or str(r).lower()=='true') else 'false')
    print('\t'.join([str(e.get('type','new')),str(e.get('sid','') or ''),str(e.get('model','') or ''),str(e.get('effort','') or ''),r]))
PYEOF
  else
    bl="$(get bootLaunch)"; [[ -z "$bl" ]] && bl=off
    [[ "$bl" == off ]] && return
    br="$(get bootRemote)"; case "$br" in true) r=true;; ask) r=ask;; *) r=false;; esac
    if [[ "$bl" == new ]]; then printf 'new\t\tsonnet\tmedium\t%s\n' "$r"
    elif [[ "$bl" == last ]]; then printf 'last\t\t\t\t%s\n' "$r"
    else printf 'resume\t%s\t\t\t%s\n' "$bl" "$r"; fi
  fi
}

LINES=(); while IFS= read -r line; do [[ -n "$line" ]] && LINES+=("$line"); done < <(emit_entries)
[[ ${#LINES[@]} -eq 0 ]] && exit 0

open_term(){ local cwd="$1"; shift; local cmd="cd \"$cwd\" && command claude $*"
  if [[ "$(uname)" == "Darwin" ]]; then osascript -e "tell application \"Terminal\" to do script \"$cmd\"" >/dev/null 2>&1
  elif command -v x-terminal-emulator >/dev/null 2>&1; then x-terminal-emulator -e bash -lc "$cmd" >/dev/null 2>&1 &
  elif command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal -- bash -lc "$cmd" >/dev/null 2>&1 &
  else nohup bash -lc "$cmd" >/dev/null 2>&1 & fi
}

n=${#LINES[@]}
for idx in "${!LINES[@]}"; do
  IFS=$'\t' read -r type sid model effort remote <<< "${LINES[$idx]}"
  args=(); cwd="$HOME"
  if [[ "$type" == last ]]; then
    f="$(find "$PJ" -name '*.jsonl' 2>/dev/null | grep -v session-sync-titlegen | xargs -r ls -1t 2>/dev/null | head -n1)"
    [[ -n "$f" ]] && { args+=(--resume "$(basename "$f" .jsonl)"); c="$(cwd_of "$f")"; [[ -n "$c" ]] && cwd="$c"; }
  elif [[ "$type" == resume ]]; then
    [[ -n "$sid" ]] && { args+=(--resume "$sid"); f="$(find "$PJ" -name "$sid.jsonl" 2>/dev/null | head -n1)"; [[ -n "$f" ]] && { c="$(cwd_of "$f")"; [[ -n "$c" ]] && cwd="$c"; }; }
  else
    [[ -n "$model" ]] && args+=(--model "$model"); [[ -n "$effort" ]] && args+=(--effort "$effort")
  fi
  inline=0; [[ $idx -eq $((n-1)) ]] && inline=1
  rc=0
  if [[ "$remote" == true ]]; then rc=1
  elif [[ "$remote" == ask && $inline -eq 1 ]]; then
    echo "リモート操作(スマホ/claude.ai)を有効にしますか? [y/N] (8秒で N)"; read -r -t 8 ans || ans=""; [[ "$ans" =~ ^[yY]$ ]] && rc=1
  fi
  [[ $rc -eq 1 ]] && args+=(--remote-control)
  echo "▶ claude ${args[*]:-}  (cwd=$cwd)"
  [[ $DRY -eq 1 ]] && continue
  if [[ $inline -eq 1 ]]; then cd "$cwd" 2>/dev/null || true; exec command claude "${args[@]}"
  else open_term "$cwd" "${args[@]}"; fi
done
