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
        print("  %d) %s  リモート=%s"%(i,d,e.get('remote',False)))
elif op in ('add','set'):
    rest=sys.argv[3:]; idx=None
    if op=='set': idx=int(rest[0]); rest=rest[1:]
    t,sid,model,effort,remote=rest[0],rest[1],rest[2],rest[3],rest[4]
    e={"type":t}
    if t=='resume': e['sid']=sid
    if t=='new':
        e['model']=model or 'sonnet'
        if effort and effort!='none': e['effort']=effort
    e['remote']= True if remote=='true' else (False if remote=='false' else 'ask')
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
  local idx="$1" ty t sid="" model="" effort="" rm remote
  echo; echo "種類: 1) 新規(壁打ち)  2) 最近の会話を再開  3) 特定の会話"
  read -rp "種類 [1]: " ty; case "$ty" in 2) t=last;; 3) t=resume;; *) t=new;; esac
  if [[ "$t" == new ]]; then
    read -rp "モデル [sonnet] (例 opus / claude-sonnet-4-6): " model; [[ -z "$model" ]] && model=sonnet
    read -rp "思考深度 low/medium/high/xhigh/max ([medium], none=指定なし): " effort; [[ -z "$effort" ]] && effort=medium
  elif [[ "$t" == resume ]]; then
    sid="$(pick_session)"; [[ -z "$sid" ]] && { echo "会話未選択。中止。"; sleep 1; return; }
  fi
  read -rp "リモート 1) ON  2) OFF  3) 起動時に尋ねる [3]: " rm; case "$rm" in 1) remote=true;; 2) remote=false;; *) remote=ask;; esac
  if [[ "$idx" == "-1" ]]; then pyjson add "$BJ" "$t" "$sid" "$model" "$effort" "$remote"
  else pyjson set "$BJ" "$idx" "$t" "$sid" "$model" "$effort" "$remote"; fi
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

guide_share(){ clear; echo "=== 共有を開始 / 再リンク(履歴・スキル) ==="
  echo "現在: transport=$(get transport)  projects=$(get shareProjects)  skills=$(get shareSkills)  mcp=$(get shareMcp)"
  echo "保存先(share): $(get share)"; echo
  echo "安全のためここでは実行しません。次の手順で:"
  echo "  1) Claude をすべて終了(起動中はリンク化に失敗)"
  echo "  2) 予行演習: bash \"$DIR/setup.sh\" --phase link"
  echo "  3) 実行:     bash \"$DIR/setup.sh\" --phase link --yes"
  echo "  共有対象変更: bash \"$DIR/setup.sh\" --skills --mcp など"
  read -rp "Enter で戻る。" _ || true; }
guide_mcp(){ clear; echo "=== MCP を共有(書き出し / 取り込み) ==="
  echo "~/.claude.json はリンクせず mcpServers のみ同期。"; echo
  echo "  状態:     bash \"$DIR/mcp-sync.sh\" --status"
  echo "  書き出し: bash \"$DIR/mcp-sync.sh\" --export   (秘密があれば --yes か --strip-env)"
  echo "  取り込み: bash \"$DIR/mcp-sync.sh\" --import --yes"
  read -rp "Enter で戻る。" _ || true; }
guide_restore(){ clear; echo "=== 元の履歴先へ復元(共有リンクを解除) ==="
  for n in projects skills; do
    p="$CLAUDE/$n"
    if [[ -L "$p" ]]; then echo "  ~/.claude/$n: リンク→ $(readlink "$p")"
      echo "   復元(Claude 終了後): rm \"$p\"; [[ -d \"${p}_local_old\" ]] && mv \"${p}_local_old\" \"$p\""
    else echo "  ~/.claude/$n: ローカル(リンクなし)"; fi
  done
  echo; echo "※ 実体データは共有フォルダ側に残ります(復元はリンク解除のみ)。"
  read -rp "Enter で戻る。" _ || true; }

while true; do
  AT="$(get autoTitle)"; [[ "$AT" == false ]] && ATD=OFF || ATD=ON
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
  echo "[表示・操作]"
  echo "  3) 同期の状態を表示(方式・保存先・共有中の項目)"
  echo "  4) 共有を開始 / 再リンク(履歴・スキル)"
  echo "  5) MCP を共有(書き出し / 取り込み)"
  echo "  6) 元の履歴先へ復元(リンク解除)"
  echo
  echo "  番号を入力   q) 終了"
  read -rp "> " ch || exit 0
  case "$ch" in
    1) manage_autostart;;
    2) [[ "$AT" == false ]] && setkv autoTitle true || setkv autoTitle false;;
    3) clear; bash "$DIR/setup.sh" --status; read -rp "Enter で戻る。" _ || true;;
    4) guide_share;;
    5) guide_mcp;;
    6) guide_restore;;
    q) exit 0;;
  esac
done
