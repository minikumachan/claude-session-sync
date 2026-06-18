#!/usr/bin/env bash
#  claude-session-sync : 履歴ブラウザ UI (macOS / Linux)  —  `claude -h` から起動
#  python curses による タブ式・ページ式・遅延読込の対話UI(キーボード＋マウス対応)。
#  タブ: このプロジェクト / 全履歴 / 最近7日。 ↑↓選択 ←→タブ PgUp/PgDn頁 Enter再開 /検索 q終了。マウス: ホイール/クリック。
set -uo pipefail
PY="$(command -v python3 || command -v python || true)"; [[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
SHARE="$(get share)"; RF="$(mktemp)"
RESULTFILE="$RF" PROJECTS="$PROJECTS" SHARE="$SHARE" CWDP="$(pwd)" "$PY" - <<'PYEOF'
import curses,os,json,glob,re,datetime
root=os.environ['PROJECTS']; share=os.environ.get('SHARE',''); cwdp=os.environ.get('CWDP','')
def enc(s): return re.sub(r'[^A-Za-z0-9]','-',s)
cwdkey=enc(cwdp)
def load_map(p):
    m={}
    if p and os.path.exists(p):
        for l in open(p,encoding='utf-8',errors='replace'):
            a=l.rstrip('\n').split('\t',1)
            if len(a)==2: m[a[0]]=a[1]
    return m
devmap=load_map(os.path.join(share,'sessions','devices.map')) if share else {}
titlemap=load_map(os.path.join(share,'sessions','titles.map')) if share else {}
def all_sessions():
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
    return ' '.join(b['text'] for b in c if isinstance(b,dict) and b.get('type')=='text' and b.get('text')) if isinstance(c,list) else ''
def dev_from_cwd(c):
    if not c: return 'unknown'
    if re.match(r'^[A-Za-z]:\\',c):
        m=re.match(r'^[A-Za-z]:\\Users\\([^\\]+)',c); return 'Win/'+(m.group(1) if m else '?')
    m=re.match(r'^/Users/([^/]+)',c)
    if m: return 'Mac/'+m.group(1)
    m=re.match(r'^/home/([^/]+)',c)
    if m: return 'Linux/'+m.group(1)
    if c.startswith('/root'): return 'Linux/root'
    return 'unknown'
cache={}
def scan(f):
    if f in cache: return cache[f]
    cwd='';prev='';ai=''
    try:
        for i,l in enumerate(open(f,encoding='utf-8',errors='replace')):
            if i>120: break
            l=l.strip()
            if not l: continue
            try:o=json.loads(l)
            except:continue
            if not cwd and o.get('cwd'): cwd=str(o['cwd'])
            if not ai and o.get('type')=='ai-title' and o.get('aiTitle'): ai=str(o['aiTitle'])
            if not prev and (o.get('message') or {}).get('role')=='user':
                t=msgtext(o)
                if t: prev=re.sub(r'\s+',' ',t).strip()
            if cwd and prev and ai: break
    except Exception: pass
    sid=os.path.splitext(os.path.basename(f))[0]
    dev=devmap.get(sid) or dev_from_cwd(cwd)
    ttl=titlemap.get(sid) or ai or prev or '(no title)'
    r=(sid,dev,ttl); cache[f]=r; return r
ALL=all_sessions()
now=datetime.datetime.now().timestamp()
TABS=['このプロジェクト','全履歴','最近7日']
def tabfiles(ti,search):
    if ti==0: fs=[f for f in ALL if os.path.basename(os.path.dirname(f))==cwdkey]
    elif ti==2: fs=[f for f in ALL if os.path.getmtime(f)>=now-7*86400]
    else: fs=list(ALL)
    if search:
        s=search.lower()
        fs=[f for f in fs if s in os.path.basename(os.path.dirname(f)).lower() or s in os.path.basename(f).lower() or (f in cache and s in cache[f][2].lower())]
    return fs
PAL=[6,2,3,5,4,1,7]  # cyan,green,yellow,magenta,blue,red,white
def colorpair(dev):
    h=0
    for ch in dev: h=h*31+ord(ch)
    return (abs(h)%len(PAL))+1
def run(stdscr):
    curses.curs_set(0); curses.use_default_colors()
    for i,c in enumerate(PAL): curses.init_pair(i+1,c,-1)
    try: curses.mousemask(curses.ALL_MOUSE_EVENTS|curses.REPORT_MOUSE_POSITION)
    except Exception: pass
    ti=0; sel=0; top=0; search=''
    files=tabfiles(ti,search)
    while True:
        h,w=stdscr.getmaxyx(); rows=max(3,h-3)
        if sel>=len(files): sel=max(0,len(files)-1)
        if sel<0: sel=0
        if sel<top: top=sel
        if sel>=top+rows: top=sel-rows+1
        if top<0: top=0
        stdscr.erase()
        tabline=''
        for i,t in enumerate(TABS): tabline+=('[ %s ]'%t if i==ti else '  %s  '%t)
        stdscr.addnstr(0,0,tabline,w-1,curses.A_BOLD)
        total=len(files); page=top//rows+1; pages=max(1,(total+rows-1)//rows)
        hdr='ページ %d/%d  全 %d 件%s   ↑↓選択 ←→タブ PgUp/PgDn頁 Enter再開 /検索 q終了'%(page,pages,total,('  検索:'+search if search else ''))
        stdscr.addnstr(1,0,hdr,w-1,curses.A_DIM)
        for r in range(rows):
            idx=top+r
            if idx>=total: continue
            sid,dev,ttl=scan(files[idx])
            up=datetime.datetime.fromtimestamp(os.path.getmtime(files[idx])).strftime('%m-%d %H:%M')
            line='%s %4d %s  %-12.12s  %s'%('>' if idx==sel else ' ',idx+1,up,dev,ttl)
            attr=curses.A_REVERSE if idx==sel else curses.color_pair(colorpair(dev))
            try: stdscr.addnstr(2+r,0,line,w-1,attr)
            except curses.error: pass
        stdscr.refresh()
        c=stdscr.getch()
        if c in (ord('q'),27): return None
        elif c==curses.KEY_UP: sel-=1
        elif c==curses.KEY_DOWN: sel+=1
        elif c==curses.KEY_LEFT: ti=(ti-1)%len(TABS); sel=0;top=0; files=tabfiles(ti,search)
        elif c==curses.KEY_RIGHT: ti=(ti+1)%len(TABS); sel=0;top=0; files=tabfiles(ti,search)
        elif c==curses.KEY_NPAGE: sel=min(total-1,top+rows); top=sel
        elif c==curses.KEY_PPAGE: top=max(0,top-rows); sel=top
        elif c in (curses.KEY_ENTER,10,13):
            if files: return files[sel]
        elif c==ord('/'):
            curses.echo(); curses.curs_set(1); stdscr.addnstr(h-1,0,'検索: '+' '*(w-7),w-1)
            stdscr.move(h-1,4); search=stdscr.getstr(h-1,4,60).decode('utf-8','replace').strip()
            curses.noecho(); curses.curs_set(0); sel=0;top=0; files=tabfiles(ti,search)
        elif c==curses.KEY_MOUSE:
            try:
                _,mx,my,_,bs=curses.getmouse()
                if bs & curses.BUTTON4_PRESSED: sel=max(0,sel-3)
                elif (hasattr(curses,'BUTTON5_PRESSED') and bs & curses.BUTTON5_PRESSED): sel=min(total-1,sel+3)
                elif bs & curses.BUTTON1_CLICKED:
                    r=my-2
                    if 0<=r<rows and top+r<total: sel=top+r; return files[sel]
            except Exception: pass
sel_file=None
try:
    sel_file=curses.wrapper(run)
except Exception:
    sel_file=None
if sel_file:
    sid=os.path.splitext(os.path.basename(sel_file))[0]
    open(os.environ['RESULTFILE'],'w',encoding='utf-8').write(sel_file+'\t'+sid)
PYEOF
res="$(cat "$RF" 2>/dev/null)"; rm -f "$RF"
[[ -z "$res" ]] && exit 0
file="${res%%$'\t'*}"; sid="${res##*$'\t'}"
enc="$(printf '%s' "$(pwd)" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$PROJECTS/$enc"
dest="$PROJECTS/$enc/$sid.jsonl"; [[ "$file" != "$dest" ]] && cp "$file" "$dest"
exec command claude --resume "$sid"
