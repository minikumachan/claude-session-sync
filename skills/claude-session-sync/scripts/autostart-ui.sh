#!/usr/bin/env bash
#  claude-session-sync : 自動起動 / リモート設定の対話メニュー (macOS / Linux)
#    `claude -a` から起動。複数の起動項目(種類/モデル/思考深度/リモート)を番号メニューで管理。
#    起動項目は ~/.claude/session-sync.boot.json に保存し、登録は install-autostart.sh --apply に委譲。
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
    try:
        a=json.load(open(f,encoding='utf-8')); return a if isinstance(a,list) else ([a] if isinstance(a,dict) else [])
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

edit_entry(){  # $1 = idx(0始まり) または -1(追加)
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

# 作業用に boot.json を用意(無ければ空配列)
[[ -f "$BJ" ]] || echo "[]" > "$BJ"
CHECK="$(get bootCheckMulti)"; [[ -z "$CHECK" ]] && CHECK=true
WATCH="$(get remoteWatch)"; [[ -z "$WATCH" ]] && WATCH=false

while true; do
  clear
  echo "=============================================="
  echo "  Claude 自動起動 / リモート設定   (claude -a)"
  echo "=============================================="
  echo
  echo "ログオン時に起動する会話:"
  pyjson list "$BJ"
  echo
  echo "共通: 多重起動チェック=$CHECK   スマホからの起動(常駐)=$WATCH"
  echo
  echo "a) 追加   e<番号>) 編集(例 e1)   d<番号>) 削除(例 d1)"
  echo "m) 多重起動チェック切替   w) スマホからの起動 切替   s) 保存して有効化   q) 保存せず終了"
  read -rp "> " cmd || exit 0
  case "$cmd" in
    a) edit_entry -1;;
    e*) idx="${cmd#e}"; [[ "$idx" =~ ^[0-9]+$ ]] && edit_entry $((idx-1));;
    d*) idx="${cmd#d}"; [[ "$idx" =~ ^[0-9]+$ ]] && pyjson del "$BJ" $((idx-1));;
    m) [[ "$CHECK" == true ]] && CHECK=false || CHECK=true;;
    w) [[ "$WATCH" == true ]] && WATCH=false || WATCH=true;;
    s) [[ "$(pyjson count "$BJ")" -eq 0 ]] && rm -f "$BJ"
       setkv bootCheckMulti "$CHECK"; setkv remoteWatch "$WATCH"
       clear; echo "保存して登録します…"; echo; bash "$DIR/install-autostart.sh" --apply
       echo; read -rp "Enter で閉じる。" _ || true; exit 0;;
    q) exit 0;;
  esac
done
