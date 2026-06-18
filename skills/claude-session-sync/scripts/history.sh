#!/usr/bin/env bash
#  claude-session-sync : 全プロジェクト横断の履歴ビューア (macOS / Linux)
#  どのカレントディレクトリからでも全履歴を一覧/閲覧/再開できる(~/.claude/projects を直接読む)。
#    list | view <#|id> | resume <#|id> | path <#|id>   [--limit N] [--grep TEXT]
set -uo pipefail
PROJECTS="$HOME/.claude/projects"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
CMD="${1:-list}"; ID="${2:-}"
LIMIT=60; GREP=""
args=("$@")
for ((i=0;i<${#args[@]};i++)); do
  case "${args[$i]}" in
    --limit) LIMIT="${args[$((i+1))]:-60}";;
    --grep)  GREP="${args[$((i+1))]:-}";;
  esac
done
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }

run_py(){ PROJECTS="$PROJECTS" CMD="$1" ID="$2" LIMIT="$LIMIT" GREP="$GREP" "$PY" - <<'PYEOF'
import os, json, glob, re
root=os.environ['PROJECTS']; cmd=os.environ['CMD']; idarg=os.environ.get('ID','');
limit=int(os.environ.get('LIMIT') or 60); grep=os.environ.get('GREP','')
def sessions():
    fs=[]
    for f in glob.glob(os.path.join(root,'**','*.jsonl'), recursive=True):
        d=os.path.basename(os.path.dirname(f)); b=os.path.splitext(os.path.basename(f))[0]
        if d=='subagents' or d.startswith('wf_') or b.startswith('agent-') or b=='journal': continue
        fs.append(f)
    fs.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return fs
def msgtext(o):
    c=(o.get('message') or {}).get('content')
    if c is None: return ''
    if isinstance(c,str): return c
    out=[]
    if isinstance(c,list):
        for b in c:
            if isinstance(b,dict) and b.get('type')=='text' and b.get('text'): out.append(b['text'])
    return '\n'.join(out)
def first_user(f):
    try:
        with open(f,encoding='utf-8',errors='replace') as fh:
            for line in fh:
                line=line.strip()
                if not line: continue
                try: o=json.loads(line)
                except: continue
                if (o.get('message') or {}).get('role')=='user':
                    t=msgtext(o)
                    if t: return re.sub(r'\s+',' ',t).strip()
    except FileNotFoundError: pass
    return ''
def find(key):
    s=sessions()
    if key.isdigit() and 1<=int(key)<=len(s): return s[int(key)-1]
    for f in s:
        b=os.path.splitext(os.path.basename(f))[0]
        if b==key or b.startswith(key): return f
    return None
import datetime
if cmd=='list':
    s=sessions(); i=0
    print("%-3s %-12s %8s %-42s %-9s %s"%('#','Updated','KB','Project','Session','Preview'))
    for f in s[:limit]:
        proj=os.path.basename(os.path.dirname(f)); prev=first_user(f)
        if grep and grep not in prev and grep not in proj: continue
        i+=1
        up=datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime('%m-%d %H:%M')
        kb=round(os.path.getsize(f)/1024)
        b=os.path.splitext(os.path.basename(f))[0][:8]
        print("%-3d %-12s %8d %-42.42s %-9s %s"%(i,up,kb,proj,b,prev[:60]))
elif cmd=='view':
    f=find(idarg)
    if not f: print('見つかりません: '+idarg); raise SystemExit(1)
    print('=== %s [%s] ==='%(os.path.splitext(os.path.basename(f))[0], os.path.basename(os.path.dirname(f))))
    with open(f,encoding='utf-8',errors='replace') as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try: o=json.loads(line)
            except: continue
            role=(o.get('message') or {}).get('role')
            if role not in ('user','assistant'): continue
            t=msgtext(o)
            if t: print('\n['+role+']\n'+t)
elif cmd=='find':
    f=find(idarg)
    if not f: raise SystemExit(1)
    print(f+'\t'+os.path.splitext(os.path.basename(f))[0])
PYEOF
}

case "$CMD" in
  list) run_py list "" ;;
  view) [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }; run_py view "$ID" ;;
  path) [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }; run_py find "$ID" | cut -f1 ;;
  resume)
    [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }
    out="$(run_py find "$ID")" || { echo "見つかりません: $ID" >&2; exit 1; }
    src="${out%%$'\t'*}"; sid="${out##*$'\t'}"
    enc="$(printf '%s' "$(pwd)" | sed 's/[^A-Za-z0-9]/-/g')"
    mkdir -p "$PROJECTS/$enc"
    dest="$PROJECTS/$enc/$sid.jsonl"
    [[ "$src" != "$dest" ]] && cp "$src" "$dest" && echo "現在のフォルダ向けに取り込みました。"
    echo "再開:"; echo "  claude --resume $sid" ;;
  *) echo "使い方: history.sh list|view|resume|path <#|id> [--limit N] [--grep TEXT]" >&2; exit 1 ;;
esac
