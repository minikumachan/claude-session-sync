#!/usr/bin/env bash
#  claude-session-sync : 設定ハブ (macOS / Linux)  —  `claude -a`
#    自動起動の管理 + 同期(履歴/スキル/MCP)状態・会話タイトル自動更新・共有開始/再リンク・
#    元の履歴先への復元 を番号メニューで扱う。破壊的操作は安全のため手順表示のみ。
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"; BJ="$CLAUDE/session-sync.boot.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PJ="$CLAUDE/projects"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup を実行してください。"; exit 0; }
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "python3 が必要です(JSON 設定の読み書きに使用)。"; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
setkv(){ local k="$1" v="$2" tmp; tmp="$(mktemp)"
  if grep -qE "^$k=" "$CFG"; then sed "s|^$k=.*|$k=$v|" "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  else cat "$CFG" > "$tmp"; printf '%s=%s\n' "$k" "$v" >> "$tmp"; mv "$tmp" "$CFG"; fi; }
SHARE="$(get share)"
title_of(){ local sid="$1" t="" m; for m in "$SHARE/sessions/titles.map" "$CLAUDE/sessions/titles.map"; do [[ -f "$m" ]] || continue; t="$(grep -F "$sid"$'\t' "$m" 2>/dev/null | head -n1 | cut -f2-)"; [[ -n "$t" ]] && break; done; [[ -z "$t" ]] && t="(無題)"; printf '%s' "$t"; }

pyjson(){ "$PY" - "$@" <<'PYEOF'
import json,sys
op=sys.argv[1]; f=sys.argv[2]
def load():
    try: a=json.load(open(f,encoding='utf-8')); return a if isinstance(a,list) else ([a] if isinstance(a,dict) else [])
    except Exception: return []
def save(a): json.dump(a, open(f,'w',encoding='utf-8'), ensure_ascii=False, indent=2)
a=load()
if op=='count': print(len(a))
elif op=='list':
    for i,e in enumerate(a,1):
        t=e.get('type','new')
        if t=='new': d="新規(壁打ち) model=%s effort=%s"%(e.get('model') or 'sonnet', e.get('effort') or '(既定)')
        elif t=='last': d="最近の会話を再開 (会話のモデル/深度を使用)"
        else: d="特定の会話 sid=%s (会話のモデル/深度を使用)"%(str(e.get('sid',''))[:8])
        perm=e.get('permission','') or 'default'
        if perm!='default': d=d+("  権限=%s"%perm)
        print("  %d) %s  リモート=%s"%(i,d,e.get('remote',False)))
elif op in ('add','set'):
    rest=sys.argv[3:]; idx=None
    if op=='set': idx=int(rest[0]); rest=rest[1:]
    t,sid,model,effort,remote=rest[0],rest[1],rest[2],rest[3],rest[4]
    permission=rest[5] if len(rest)>5 else 'default'
    e={"type":t}
    if t=='resume': e['sid']=sid
    if t=='new':
        e['model']=model or 'sonnet'
        if effort and effort!='none': e['effort']=effort
    e['remote']= True if remote=='true' else (False if remote=='false' else 'ask')
    if permission and permission!='default': e['permission']=permission
    if op=='add': a.append(e)
    elif idx is not None and 0<=idx<len(a): a[idx]=e
    save(a)
elif op=='del':
    idx=int(sys.argv[3])
    if 0<=idx<len(a): a.pop(idx); save(a)
PYEOF
}

pick_session(){
  local files=() i=1 f n
  while IFS= read -r f; do files+=("$f"); done < <(find "$PJ" -name '*.jsonl' 2>/dev/null | grep -v session-sync-titlegen | xargs -r ls -1t 2>/dev/null | head -n 15)
  [[ ${#files[@]} -eq 0 ]] && { echo ""; return; }
  for f in "${files[@]}"; do echo "  $i) $(title_of "$(basename "$f" .jsonl)")" >&2; i=$((i+1)); done
  read -rp "番号(空=取消): " n >&2 || true
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#files[@]} )); then basename "${files[$((n-1))]}" .jsonl; fi
}
edit_entry(){
  local idx="$1" ty t sid="" model="" effort="" rm remote pm permission
  echo; echo "種類: 1) 新規(壁打ち)  2) 最近の会話を再開  3) 特定の会話"
  read -rp "種類 [1]: " ty; case "$ty" in 2) t=last;; 3) t=resume;; *) t=new;; esac
  if [[ "$t" == new ]]; then
    read -rp "モデル [sonnet] (例 opus / claude-sonnet-4-6): " model; [[ -z "$model" ]] && model=sonnet
    read -rp "思考深度 low/medium/high/xhigh/max ([medium], none=指定なし): " effort; [[ -z "$effort" ]] && effort=medium
  elif [[ "$t" == resume ]]; then
    sid="$(pick_session)"; [[ -z "$sid" ]] && { echo "会話未選択。中止。"; sleep 1; return; }
  fi
  read -rp "リモート 1) ON  2) OFF  3) 起動時に尋ねる [3]: " rm; case "$rm" in 1) remote=true;; 2) remote=false;; *) remote=ask;; esac
  echo "権限: 1) 既定(都度確認)  2) プラン(読取中心)  3) 編集自動承認  4) 自動  5) 確認しない  6) ⚠バイパス  7) ⚠⚠完全フリー(env取得/コピー可)"
  read -rp "権限 [1]: " pm
  case "$pm" in 2) permission=plan;; 3) permission=acceptEdits;; 4) permission=auto;; 5) permission=dontAsk;; 6) permission=bypassPermissions;; 7) permission=full;; *) permission=default;; esac
  if [[ "$permission" == bypassPermissions || "$permission" == full ]]; then
    echo "⚠ 上位権限です。$permission は権限チェックを大きく緩めます(full は env 値の取得・コピー・任意コマンド実行まで無確認)。"
    read -rp "本当にこの権限にしますか? [y/N]: " yn; [[ "$yn" =~ ^[yY]$ ]] || permission=default
  fi
  if [[ "$idx" == "-1" ]]; then pyjson add "$BJ" "$t" "$sid" "$model" "$effort" "$remote" "$permission"
  else pyjson set "$BJ" "$idx" "$t" "$sid" "$model" "$effort" "$remote" "$permission"; fi
}

manage_autostart(){
  [[ -f "$BJ" ]] || echo "[]" > "$BJ"
  local CHECK; CHECK="$(get bootCheckMulti)"; [[ -z "$CHECK" ]] && CHECK=true
  while true; do
    clear
    echo "=== 自動起動する会話の管理 ==="; echo
    pyjson list "$BJ"; echo
    echo "共通: 多重起動チェック=$CHECK"; echo
    echo "a) 追加   e<番号>) 編集(例 e1)   d<番号>) 削除(例 d1)"
    echo "m) 多重起動チェック切替   s) 保存して有効化   q) 戻る"
    read -rp "> " cmd || return
    case "$cmd" in
      a) edit_entry -1;;
      e*) idx="${cmd#e}"; [[ "$idx" =~ ^[0-9]+$ ]] && edit_entry $((idx-1));;
      d*) idx="${cmd#d}"; [[ "$idx" =~ ^[0-9]+$ ]] && pyjson del "$BJ" $((idx-1));;
      m) [[ "$CHECK" == true ]] && CHECK=false || CHECK=true;;
      s) [[ "$(pyjson count "$BJ")" -eq 0 ]] && rm -f "$BJ"
         setkv bootCheckMulti "$CHECK"
         clear; echo "保存して登録します…"; echo; bash "$DIR/install-autostart.sh" --apply
         read -rp "Enter で戻る。" _ || true; return;;
      q) return;;
    esac
  done
}

confirm_danger(){ local title="$1"; shift; clear; echo "⚠ 確認が必要な操作: $title"; echo "----------------------------------------"; echo
  for l in "$@"; do echo "  ・$l"; done; echo
  read -rp "実行する=y / やめる=n: " yn; [[ "$yn" =~ ^[yY]$ ]]; }
status_panel(){ clear; echo "=== 同期の状態 ==="; echo
  comp(){ local n="$1" f="$2"; if [ -L "$CLAUDE/$n" ]; then echo "共有中(リンク → $(readlink "$CLAUDE/$n"))"; elif [ "$f" = true ]; then echo "設定ONだが未リンク"; else echo "ローカル(共有なし)"; fi; }
  printf "  %-22s: %s\n" "同期方式(transport)" "$(get transport)"
  printf "  %-22s: %s\n" "保存先(共有フォルダ)" "$(get share)"
  printf "  %-22s: %s\n" "会話履歴(projects)" "$(comp projects "$(get shareProjects)")"
  printf "  %-22s: %s\n" "スキル(skills)" "$(comp skills "$(get shareSkills)")"
  printf "  %-22s: %s\n" "MCP定義(mcp)" "$([ "$(get shareMcp)" = true ] && echo '共有ON' || echo '共有なし')"
  printf "  %-22s: %s\n" "会話タイトル自動更新" "$([ "$(get autoTitle)" = false ] && echo OFF || echo ON)"
  printf "  %-22s: %s\n" "デバイス切替の通知" "$([ "$(get deviceSwitchNotice)" = false ] && echo OFF || echo ON)"
  echo; read -rp "Enter で戻る。" _ || true; }
do_share(){
  local p s m; [ "$(get shareProjects)" = false ] && p=0 || p=1; [ "$(get shareSkills)" = true ] && s=1 || s=0; [ "$(get shareMcp)" = true ] && m=1 || m=0
  while true; do
    clear; echo "=== 共有を開始 / 変更 / 再リンク ==="; echo "保存先(共有): $(get share)"
    echo "実行は破壊的(自動バックアップあり)。実行前に他の Claude を全終了。"; echo
    echo "  1) 会話履歴(projects): $([ $p -eq 1 ] && echo 共有する || echo 共有しない)"
    echo "  2) スキル(skills)    : $([ $s -eq 1 ] && echo 共有する || echo 共有しない)"
    echo "  3) MCP定義(mcp)      : $([ $m -eq 1 ] && echo 共有する || echo 共有しない)"
    echo "  p) 予行演習(変更しない)   y) 実行する   q) 戻る"
    read -rp "> " ch || return
    local flags=()
    case "$ch" in
      1) p=$((1-p));; 2) s=$((1-s));; 3) m=$((1-m));;
      p) [ $p -eq 1 ] && flags+=(--projects) || flags+=(--no-projects); [ $s -eq 1 ] && flags+=(--skills) || flags+=(--no-skills); [ $m -eq 1 ] && flags+=(--mcp) || flags+=(--no-mcp)
         clear; echo "予行演習(変更しません)"; echo "----------------------------------------"; echo; bash "$DIR/setup.sh" "${flags[@]}" --phase link; echo; read -rp "Enter で戻る。" _ || true;;
      y) [ $p -eq 1 ] && flags+=(--projects) || flags+=(--no-projects); [ $s -eq 1 ] && flags+=(--skills) || flags+=(--no-skills); [ $m -eq 1 ] && flags+=(--mcp) || flags+=(--no-mcp)
         if confirm_danger "共有の開始/再リンク" "~/.claude/projects 等を共有フォルダへのリンクに置換(破壊的)" "元データは *_backup_* / *_local_old に退避" "他の Claude を全終了してから実行"; then
           clear; echo "実行結果"; echo "----------------------------------------"; echo; bash "$DIR/setup.sh" "${flags[@]}" --phase all --yes; echo; read -rp "Enter で戻る。" _ || true
         fi;;
      q) return;;
    esac
  done
}
do_mcp(){
  local M="$DIR/mcp-sync.sh"
  while true; do
    clear; echo "=== MCP を共有(mcpServers のみ) ==="; echo "~/.claude.json はリンクせず mcpServers だけ同期。"; echo
    echo "  1) 状態を表示   2) 書き出す(Export)   3) 書き出す(秘密も含め・要確認)   4) 取り込む(Import・破壊的・要確認)   q) 戻る"
    read -rp "> " ch || return
    case "$ch" in
      1) clear; bash "$M" --status; echo; read -rp "Enter で戻る。" _ || true;;
      2) clear; bash "$M" --export; echo; read -rp "Enter で戻る。" _ || true;;
      3) if confirm_danger "MCP 書き出し(秘密も含む)" "env(APIキー等の秘密)も共有フォルダに書き出されます" "共有先が他人と共有されている場合は漏洩の恐れ"; then clear; bash "$M" --export --yes; echo; read -rp "Enter で戻る。" _ || true; fi;;
      4) if confirm_danger "MCP 取り込み(Import)" "共有の mcpServers を ~/.claude.json に取り込み(破壊的)" "自動でバックアップを作成"; then clear; bash "$M" --import --yes; echo; read -rp "Enter で戻る。" _ || true; fi;;
      q) return;;
    esac
  done
}
do_restore(){
  while true; do
    clear; echo "=== 元の履歴先へ復元(共有リンクを解除) ==="
    echo "共有リンクを解除しローカルに戻します。実体データは共有側に残ります。実行前に Claude を全終了。"; echo
    for n in projects skills; do
      if [ -L "$CLAUDE/$n" ]; then echo "  $n: 共有リンク → $(readlink "$CLAUDE/$n")"; else echo "  $n: ローカル(リンクなし)"; fi
    done
    echo; echo "  1) projects を復元   2) skills を復元   q) 戻る"
    read -rp "> " ch || return
    local name=""; case "$ch" in 1) name=projects;; 2) name=skills;; q) return;; *) continue;; esac
    local lp="$CLAUDE/$name"
    if [ ! -L "$lp" ]; then clear; echo "$name は既にローカル(リンクなし)です。"; read -rp "Enter で戻る。" _ || true; continue; fi
    local target; target="$(readlink "$lp")"
    if confirm_danger "$name をローカルへ復元" "$lp の共有リンクを解除しローカルに戻す" "実体は共有側($target)に残る" "他の Claude を全終了してから実行"; then
      clear; echo "$name の復元結果"; echo "----------------------------------------"
      if rm "$lp" 2>/dev/null; then
        if [ -d "${lp}_local_old" ]; then mv "${lp}_local_old" "$lp"; echo "✔ ${name}_local_old を $lp に書き戻しました。"
        else mkdir -p "$lp"; cp -a "$target/." "$lp/" 2>/dev/null && echo "✔ 共有($target)から $lp へコピーして復元しました。" || echo "⚠ コピーに一部失敗。$target を確認してください。"; fi
        echo "(共有側のデータはそのまま残っています)"
      else echo "⛔ リンク解除に失敗(使用中?)。Claude を全終了してから再実行してください。"; fi
      echo; read -rp "Enter で戻る。" _ || true
    fi
  done
}

while true; do
  AT="$(get autoTitle)"; [[ "$AT" == false ]] && ATD=OFF || ATD=ON
  DN="$(get deviceSwitchNotice)"; [[ "$DN" == false ]] && DND=OFF || DND=ON
  N="$(pyjson count "$BJ" 2>/dev/null || echo 0)"
  clear
  echo "=============================================="
  echo "  Claude セッション同期 — 設定   (claude -a)"
  echo "=============================================="
  echo
  echo "[自動起動]"
  echo "  1) 自動起動する会話を管理 ($N 件)"
  echo "[同期]"
  echo "  2) 会話タイトルの自動更新: $ATD  (切替)"
  echo "  3) デバイス切替の通知    : $DND  (切替)"
  echo "[表示・操作]"
  echo "  4) 同期の状態を表示(方式・保存先・共有中の項目)"
  echo "  5) 共有を開始 / 再リンク(履歴・スキル)"
  echo "  6) MCP を共有(書き出し / 取り込み)"
  echo "  7) 元の履歴先へ復元(リンク解除)"
  echo
  echo "  番号を入力   q) 終了"
  read -rp "> " ch || exit 0
  case "$ch" in
    1) manage_autostart;;
    2) [[ "$AT" == false ]] && setkv autoTitle true || setkv autoTitle false;;
    3) [[ "$DN" == false ]] && setkv deviceSwitchNotice true || setkv deviceSwitchNotice false;;
    4) status_panel;;
    5) do_share;;
    6) do_mcp;;
    7) do_restore;;
    q) exit 0;;
  esac
done
