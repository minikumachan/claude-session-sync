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
    print('\t'.join([str(e.get('type','new')),str(e.get('sid','') or ''),str(e.get('model','') or ''),str(e.get('effort','') or ''),r,str(e.get('permission','') or '')]))
PYEOF
  else
    bl="$(get bootLaunch)"; [[ -z "$bl" ]] && bl=off
    [[ "$bl" == off ]] && return
    br="$(get bootRemote)"; case "$br" in true) r=true;; ask) r=ask;; *) r=false;; esac
    if [[ "$bl" == new ]]; then printf 'new\t\tsonnet\tmedium\t%s\t\n' "$r"
    elif [[ "$bl" == last ]]; then printf 'last\t\t\t\t%s\t\n' "$r"
    else printf 'resume\t%s\t\t\t%s\t\n' "$bl" "$r"; fi
  fi
}

LINES=(); while IFS= read -r line; do [[ -n "$line" ]] && LINES+=("$line"); done < <(emit_entries)
[[ ${#LINES[@]} -eq 0 ]] && exit 0

# セキュリティ: cwd と各引数を printf %q でシェルエスケープしてからコマンド文字列を組む(bash -lc/osascript での再パース時のコマンド注入を防ぐ)。
open_term(){ local cwd="$1"; shift
  local qc; printf -v qc '%q' "$cwd"
  local cmd="cd $qc && command claude"
  local a qa; for a in "$@"; do printf -v qa '%q' "$a"; cmd="$cmd $qa"; done
  if [[ "$(uname)" == "Darwin" ]]; then
    local esc=${cmd//\\/\\\\}; esc=${esc//\"/\\\"}   # AppleScript 文字列リテラル用に \ と " をエスケープ
    osascript -e "tell application \"Terminal\" to do script \"$esc\"" >/dev/null 2>&1
  elif command -v x-terminal-emulator >/dev/null 2>&1; then x-terminal-emulator -e bash -lc "$cmd" >/dev/null 2>&1 &
  elif command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal -- bash -lc "$cmd" >/dev/null 2>&1 &
  else nohup bash -lc "$cmd" >/dev/null 2>&1 & fi
}

n=${#LINES[@]}
for idx in "${!LINES[@]}"; do
  IFS=$'\t' read -r type sid model effort remote permission <<< "${LINES[$idx]}"
  args=(); cwd="$HOME"
  rsid=""; rfile=""
  if [[ "$type" == last ]]; then
    rfile="$(find "$PJ" -name '*.jsonl' 2>/dev/null | grep -v session-sync-titlegen | xargs -r ls -1t 2>/dev/null | head -n1)"
    [[ -n "$rfile" ]] && { rsid="$(basename "$rfile" .jsonl)"; args+=(--resume "$rsid"); c="$(cwd_of "$rfile")"; [[ -n "$c" ]] && cwd="$c"; }
  elif [[ "$type" == resume ]]; then
    rsid="$sid"
    [[ -n "$rsid" ]] && { args+=(--resume "$rsid"); rfile="$(find "$PJ" -name "$rsid.jsonl" 2>/dev/null | head -n1)"; [[ -n "$rfile" ]] && { c="$(cwd_of "$rfile")"; [[ -n "$c" ]] && cwd="$c"; }; }
  else
    [[ -n "$model" ]] && args+=(--model "$model"); [[ -n "$effort" ]] && args+=(--effort "$effort")
    case "$permission" in
      full) args+=(--dangerously-skip-permissions);;
      plan|acceptEdits|auto|dontAsk|bypassPermissions) args+=(--permission-mode "$permission");;
    esac
    export CSS_LAUNCH_MODEL="$model" CSS_LAUNCH_EFFORT="$effort" CSS_LAUNCH_PERM="$permission"
  fi
  if { [[ "$type" == last ]] || [[ "$type" == resume ]]; } && [ -n "$rsid" ]; then
    optline=""
    for lf in "$SHARE/sessions/launchopts.map" "$CLAUDE/sessions/launchopts.map"; do
      [ -f "$lf" ] || continue
      l="$(grep -F "$rsid"$'\t' "$lf" 2>/dev/null | tail -n1)"; [ -n "$l" ] && { optline="$l"; break; }
    done
    im="$(printf '%s' "$optline" | cut -f2)"; ie="$(printf '%s' "$optline" | cut -f3)"; ip="$(printf '%s' "$optline" | cut -f4)"
    [ -z "$im" ] && [ -n "$rfile" ] && im="$(tail -n 400 "$rfile" 2>/dev/null | grep -oE '"model"[[:space:]]*:[[:space:]]*"claude[^"]*"' | tail -n1 | sed -E 's/.*"(claude[^"]*)".*/\1/')"
    [ -n "$im" ] && args+=(--model "$im")
    [ -n "$ie" ] && args+=(--effort "$ie")
    # permission はローカル boot.json の明示指定のみ昇格可。フォールバックの launchopts.map(共有され得る)由来の full/bypassPermissions は採用しない(汚染対策)。
    permv="$permission"
    if [ -z "$permv" ] || [ "$permv" = default ]; then
      case "$ip" in full|bypassPermissions) permv="";; *) permv="$ip";; esac
    fi
    case "$permv" in
      full) args+=(--dangerously-skip-permissions);;
      plan|acceptEdits|auto|dontAsk|bypassPermissions) args+=(--permission-mode "$permv");;
    esac
    export CSS_LAUNCH_MODEL="$im" CSS_LAUNCH_EFFORT="$ie" CSS_LAUNCH_PERM="$permv"
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
