#!/usr/bin/env bash
#  claude-session-sync : 全プロジェクト横断の履歴ビューア (macOS / Linux)
#  デバイス色分け＋タイトル(titles.map > ai-title > 冒頭発話)で一覧/閲覧/再開/タイトル生成。
#    list [--limit N] [--grep 語] [--device 名] | view <#|id> | resume <#|id> | title [--limit N|--all|<id>] | path <#|id>
set -uo pipefail
PROJECTS="$HOME/.claude/projects"; CFG="$HOME/.claude/session-sync.local.conf"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
CMD="${1:-list}"; ID="${2:-}"
LIMIT=40; GREP=""; DEVICE=""; ALL=0; PAGE=1; PAGESIZE=20
args=("$@")
for ((i=0;i<${#args[@]};i++)); do case "${args[$i]}" in
  --limit) LIMIT="${args[$((i+1))]:-40}";; --grep) GREP="${args[$((i+1))]:-}";;
  --device) DEVICE="${args[$((i+1))]:-}";; --all) ALL=1;;
  --page) PAGE="${args[$((i+1))]:-1}";; --pagesize) PAGESIZE="${args[$((i+1))]:-20}";;
esac; done
PY="$(command -v python3 || command -v python || true)"; [[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }
SHARE="$(get share)"; LANGOPT="$(get lang)"; [[ -z "$LANGOPT" ]] && LANGOPT=en
DEVMAP="$SHARE/sessions/devices.map"; TITLES="$SHARE/sessions/titles.map"

run_py(){ PROJECTS="$PROJECTS" PYCMD="$1" ID="$ID" LIMIT="$LIMIT" GREPV="$GREP" DEVICE="$DEVICE" PAGE="$PAGE" PAGESIZE="$PAGESIZE" DEVMAP="$DEVMAP" TITLES="$TITLES" "$PY" - <<'PYEOF'
import os,json,glob,re
root=os.environ['PROJECTS']; cmd=os.environ['PYCMD']; idarg=os.environ.get('ID','')
limit=int(os.environ.get('LIMIT') or 40); grep=os.environ.get('GREPV',''); devf=os.environ.get('DEVICE','')
def load_map(p):
    m={}
    if p and os.path.exists(p):
        for l in open(p,encoding='utf-8',errors='replace'):
            a=l.rstrip('\n').split('\t',1)
            if len(a)==2: m[a[0]]=a[1]
    return m
devmap=load_map(os.environ.get('DEVMAP','')); titles=load_map(os.environ.get('TITLES',''))
def sessions():
    fs=[]
    for f in glob.glob(os.path.join(root,'**','*.jsonl'),recursive=True):
        d=os.path.basename(os.path.dirname(f)); b=os.path.splitext(os.path.basename(f))[0]
        if d=='subagents' or d.startswith('wf_') or b.startswith('agent-') or b=='journal': continue
        fs.append(f)
    fs.sort(key=lambda p: os.path.getmtime(p), reverse=True); return fs
def msgtext(o):
    c=(o.get('message') or {}).get('content')
    if c is None: return ''
    if isinstance(c,str): return c
    return '\n'.join(b['text'] for b in c if isinstance(b,dict) and b.get('type')=='text' and b.get('text')) if isinstance(c,list) else ''
def scan(f):
    cwd='';prev='';ai=''
    try:
        for i,l in enumerate(open(f,encoding='utf-8',errors='replace')):
            if i>120: break
            l=l.strip()
            if not l: continue
            try: o=json.loads(l)
            except: continue
            if not cwd and o.get('cwd'): cwd=str(o['cwd'])
            if not ai and o.get('type')=='ai-title' and o.get('aiTitle'): ai=str(o['aiTitle'])
            if not prev and (o.get('message') or {}).get('role')=='user':
                t=msgtext(o)
                if t: prev=re.sub(r'\s+',' ',t).strip()
            if cwd and prev and ai: break
    except FileNotFoundError: pass
    return cwd,prev,ai
def dev_from_cwd(c):
    if not c: return 'unknown'
    m=re.match(r'^[A-Za-z]:\\Users\\([^\\]+)',c)
    if re.match(r'^[A-Za-z]:\\',c): return 'Win/'+(m.group(1) if m else '?')
    m=re.match(r'^/Users/([^/]+)',c);
    if m: return 'Mac/'+m.group(1)
    m=re.match(r'^/home/([^/]+)',c)
    if m: return 'Linux/'+m.group(1)
    if c.startswith('/root'): return 'Linux/root'
    return 'unknown'
PAL=['36','32','33','35','34','31','96','92','93','95','37']
def color(dev):
    h=0
    for ch in dev: h=h*31+ord(ch)
    return PAL[abs(h)%len(PAL)]
def devlabel(sid,cwd): return devmap.get(sid) or dev_from_cwd(cwd)
def title_of(sid,prev,ai): return titles.get(sid) or ai or prev or '(無題)'
def find(key):
    s=sessions()
    if key.isdigit() and 1<=int(key)<=len(s): return s[int(key)-1]
    for f in s:
        b=os.path.splitext(os.path.basename(f))[0]
        if b==key or b.startswith(key): return f
    return None
import datetime
if cmd=='list':
    import math
    s=sessions(); total=len(s); seen=set()
    page=int(os.environ.get('PAGE') or 1); ps=int(os.environ.get('PAGESIZE') or 20)
    if ps<1: ps=20
    pages=max(1, math.ceil(total/ps))
    if page<1: page=1
    if page>pages: page=pages
    start=(page-1)*ps; sl=s[start:start+ps]; idx=start
    print("ページ %d/%d  (全 %d 件 / 1ページ %d 件)"%(page,pages,total,ps))
    print("%-4s %-12s %-12s %s"%('#','Updated','Device','Title'))
    for f in sl:
        idx+=1; cwd,prev,ai=scan(f); sid=os.path.splitext(os.path.basename(f))[0]
        dev=devlabel(sid,cwd)
        if devf and devf not in dev: continue
        ttl=title_of(sid,prev,ai); proj=os.path.basename(os.path.dirname(f))
        if grep and grep not in ttl and grep not in proj: continue
        seen.add(dev)
        up=datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime('%m-%d %H:%M')
        print("%-4d %-12s \033[%sm%-12s\033[0m %s"%(idx,up,color(dev),dev[:12],ttl[:64]))
    print('\n凡例: '+' '.join('\033[%sm%s\033[0m'%(color(d),d) for d in sorted(seen)))
    nav=[]
    if page<pages: nav.append('次ページ: --page %d'%(page+1))
    if page>1: nav.append('前: --page %d'%(page-1))
    print(' / '.join(nav)+'  / --pagesize N / view <#> / resume <#>')
elif cmd=='view':
    f=find(idarg)
    if not f: print('見つかりません: '+idarg); raise SystemExit(1)
    cwd,prev,ai=scan(f); sid=os.path.splitext(os.path.basename(f))[0]; dev=devlabel(sid,cwd)
    print('=== %s ==='%title_of(sid,prev,ai)); print('%s [\033[%sm%s\033[0m] %s cwd=%s'%(sid,color(dev),dev,os.path.basename(os.path.dirname(f)),cwd))
    for l in open(f,encoding='utf-8',errors='replace'):
        l=l.strip()
        if not l: continue
        try: o=json.loads(l)
        except: continue
        r=(o.get('message') or {}).get('role')
        if r not in ('user','assistant'): continue
        t=msgtext(o)
        if t: print('\n['+r+']\n'+t)
elif cmd=='find':
    f=find(idarg)
    if not f: raise SystemExit(1)
    print(f+'\t'+os.path.splitext(os.path.basename(f))[0])
elif cmd=='need-title':
    # タイトル未生成のセッションを sid<TAB>seed で出力(生成対象)
    s=sessions()
    if idarg: s=[x for x in [find(idarg)] if x]
    elif not (os.environ.get('LIMIT')=='0'): s=s[:limit]
    cnt=0
    for f in s:
        sid=os.path.splitext(os.path.basename(f))[0]
        if sid in titles: continue
        cwd,prev,ai=scan(f); seed=(ai or prev or '').strip()
        if seed: print(sid+'\t'+seed.replace('\t',' ')[:500]); cnt+=1
PYEOF
}

case "$CMD" in
  list) run_py list ;;
  view) [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }; run_py view ;;
  path) [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }; run_py find | cut -f1 ;;
  resume)
    [[ -n "$ID" ]] || { echo "番号/IDを指定" >&2; exit 1; }
    out="$(run_py find)" || { echo "見つかりません: $ID" >&2; exit 1; }
    src="${out%%$'\t'*}"; sid="${out##*$'\t'}"
    enc="$(printf '%s' "$(pwd)" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$PROJECTS/$enc"
    dest="$PROJECTS/$enc/$sid.jsonl"; [[ "$src" != "$dest" ]] && cp "$src" "$dest" && echo "現在のフォルダ向けに取り込みました。"
    echo "再開:"; echo "  claude --resume $sid" ;;
  title)
    [[ -n "$SHARE" ]] || { echo "share 未設定。setup.sh を先に。" >&2; exit 1; }
    command -v claude >/dev/null 2>&1 || { echo "claude が見つかりません(タイトル生成に必要)。" >&2; exit 1; }
    [[ $ALL -eq 1 ]] && LIMIT=0
    mkdir -p "$SHARE/sessions"; made=0
    while IFS=$'\t' read -r sid seed; do
      [[ -z "$sid" ]] && continue
      t="$(command claude -p "Create a concise, descriptive title (max 8 words) for this conversation. Respond ONLY with the title text, in language code '$LANGOPT'. Conversation start: $seed" 2>/dev/null | head -n1 | tr -d '\r' | sed 's/^["「 ]*//;s/["」 ]*$//')"
      [[ -n "$t" ]] && { printf '%s\t%s\n' "$sid" "$t" >> "$TITLES"; made=$((made+1)); echo "✔ ${sid:0:8}  $t"; }
    done < <(run_py need-title)
    echo "生成: $made 件(言語=$LANGOPT)。history.sh list で反映。" ;;
  *) echo "使い方: history.sh list|view|resume|title|path <#|id> [--limit N] [--grep 語] [--device 名] [--all]" >&2; exit 1 ;;
esac
