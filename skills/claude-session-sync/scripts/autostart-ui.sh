#!/usr/bin/env bash
#  claude-session-sync : 自動起動 / リモート設定の対話メニュー (macOS / Linux)
#    `claude -a`(install-shell-wrap 導入時)から起動。番号入力で設定し、保存は install-autostart.sh に委譲。
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup を実行してください。"; exit 0; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
SHARE="$(get share)"; PJ="$CLAUDE/projects"

title_of(){ # $1=sid
  local sid="$1" t=""
  for m in "$SHARE/sessions/titles.map" "$CLAUDE/sessions/titles.map"; do
    [[ -f "$m" ]] || continue
    t="$(grep -F "$sid"$'\t' "$m" 2>/dev/null | head -n1 | cut -f2-)"; [[ -n "$t" ]] && break
  done
  [[ -z "$t" ]] && t="(無題)"; printf '%s' "$t"
}

# 初期値
BL="$(get bootLaunch)"; [[ -z "$BL" ]] && BL=off
BR="$(get bootRemote)"; [[ -z "$BR" ]] && BR=ask
CM="$(get bootCheckMulti)"; [[ -z "$CM" ]] && CM=true
RW="$(get remoteWatch)"; [[ -z "$RW" ]] && RW=false
SPECIFIC=""; case "$BL" in off|new|last) ;; *) SPECIFIC="$BL"; BL=specific;; esac

bl_label(){ case "$BL" in off) echo "なし(起動しない)";; new) echo "新規会話";; last) echo "最近の会話を再開";; specific) echo "特定の会話: $(title_of "$SPECIFIC")";; esac; }
br_label(){ case "$BR" in false) echo "オフ";; ask) echo "起動時に尋ねる(8秒でオフ)";; true) echo "常にオン(スマホ操作可)";; esac; }
cm_label(){ [[ "$CM" == true ]] && echo "オン(推奨)" || echo "オフ"; }
rw_label(){ [[ "$RW" == true ]] && echo "オン(スマホからトリガ起動)" || echo "オフ"; }

cycle_bl(){ case "$BL" in off) BL=new;; new) BL=last;; last) BL=specific; pick_session;; specific) BL=off;; esac; }
cycle_br(){ case "$BR" in false) BR=ask;; ask) BR=true;; true) BR=false;; esac; }
cycle_cm(){ [[ "$CM" == true ]] && CM=false || CM=true; }
cycle_rw(){ [[ "$RW" == true ]] && RW=false || RW=true; }

do_save(){
  local args=()
  case "$BL" in
    off|new|last) args+=(--launch "$BL");;
    specific) [[ -n "$SPECIFIC" ]] && args+=(--session "$SPECIFIC") || args+=(--launch last);;
  esac
  args+=(--remote-mode "$BR")
  [[ "$CM" == true ]] && args+=(--check-multi) || args+=(--no-check-multi)
  [[ "$RW" == true ]] && args+=(--watch) || args+=(--no-watch)
  clear; echo "保存して登録します…"; echo
  bash "$DIR/install-autostart.sh" "${args[@]}"
  echo; read -rp "Enter で閉じる。" _; exit 0
}

pick_session(){
  mapfile -t files < <(find "$PJ" -name '*.jsonl' 2>/dev/null | grep -v session-sync-titlegen | xargs -r ls -1t 2>/dev/null | head -n 15)
  if [[ ${#files[@]} -eq 0 ]]; then echo "会話が見つかりません。"; BL=last; sleep 1; return; fi
  echo; echo "=== 毎回起動する会話を選ぶ ==="
  local i=1
  for f in "${files[@]}"; do
    local sid; sid="$(basename "$f" .jsonl)"
    printf "  %2d) %s\n" "$i" "$(title_of "$sid")"; i=$((i+1))
  done
  read -rp "番号を入力(空=取消): " n
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#files[@]} )); then
    SPECIFIC="$(basename "${files[$((n-1))]}" .jsonl)"; BL=specific
  else
    BL=last
  fi
}

while true; do
  clear
  echo "==============================================="
  echo "  Claude 自動起動 / リモート設定   (claude -a)"
  echo "==============================================="
  echo
  echo "  1) ログイン時の自動起動  : $(bl_label)"
  echo "  2) リモート(スマホ操作)   : $(br_label)"
  echo "  3) 多重起動チェック        : $(cm_label)"
  echo "  4) スマホからの起動(常駐)  : $(rw_label)"
  echo
  echo "  数字=その項目を切替   s=保存して有効化   x=すべて解除   q=保存せず終了"
  read -rp "> " ch
  case "$ch" in
    1) cycle_bl;;
    2) cycle_br;;
    3) cycle_cm;;
    4) cycle_rw;;
    x) BL=off; RW=false; do_save;;
    s) do_save;;
    q) clear; echo "保存せず終了しました。"; exit 0;;
  esac
done
