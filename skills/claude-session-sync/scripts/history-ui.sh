#!/usr/bin/env bash
#  claude-session-sync : 履歴ブラウザ UI (macOS / Linux)  —  `claude -h` から起動
#  公式 `claude --resume` 風(❯選択・[要約][相対時刻][件数]列・下部キーヒント)＋タブ＋デバイス列。
#  python curses。 ↑↓選択 ←→タブ PgUp/PgDn頁 Enter再開 Space内容 /検索 q終了。マウス: ホイール/クリック。
set -uo pipefail
PY="$(command -v python3 || command -v python || true)"; [[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
SHARE="$(get share)"; RF="$(mktemp)"
RESULTFILE="$RF" PROJECTS="$PROJECTS" SHARE="$SHARE" CWDP="$(pwd)" "$PY" - <<'PYEOF'
import curses,os,json,glob,re,time
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
def reltime(ts):
    s=time.time()-ts
    if s<60: return 'たった今'
    if s<3600: return '%d分前'%(s//60)
    if s<86400: return '%d時間前'%(s//3600)
    if s<2592000: return '%d日前'%(s//86400)
    return '%dヶ月前'%(s//2592000)
cache={}
def scan(f):
    if f in cache: return cache[f]
    cwd='';prev='';ai='';msgs=0
    try:
        for l in open(f,encoding='utf-8',errors='replace'):
            if not l.strip(): continue
            if '"type":"user"' in l or '"type":"assistant"' in l: msgs+=1
            if cwd and ai and prev: continue
            try:o=json.loads(l)
            except:continue
            if not cwd and o.get('cwd'): cwd=str(o['cwd'])
            if not ai and o.get('type')=='ai-title' and o.get('aiTitle'): ai=str(o['aiTitle'])
            if not prev and (o.get('message') or {}).get('role')=='user':
                t=msgtext(o)
                if t: prev=re.sub(r'\s+',' ',t).strip()
    except Exception: pass
    sid=os.path.splitext(os.path.basename(f))[0]
    dev=devmap.get(sid) or dev_from_cwd(cwd)
    ttl=titlemap.get(sid) or ai or prev or '(no title)'
    r=(sid,dev,ttl,msgs,os.path.getmtime(f)); cache[f]=r; return r
ALL=all_sessions(); now=time.time()
TABS=['このプロジェクト','全履歴','最近7日']
def tabfiles(ti,search):
    if ti==0: fs=[f for f in ALL if os.path.basename(os.path.dirname(f))==cwdkey]
    elif ti==2: fs=[f for f in ALL if os.path.getmtime(f)>=now-7*86400]
    else: fs=list(ALL)
    if search:
        s=search.lower()
        fs=[f for f in fs if s in os.path.basename(os.path.dirname(f)).lower() or s in os.path.basename(f).lower() or (f in cache and s in cache[f][2].lower())]
    return fs
PAL=[6,2,3,5,4,1,7]
def cp(dev):
    h=0
    for ch in dev: h=h*31+ord(ch)
    return (abs(h)%len(PAL))+1
def disp(s,n):  # 全角を考慮せず単純truncate
    return s if len(s)<=n else s[:n-1]+'…'
def preview(stdscr,f):
    stdscr.erase(); h,w=stdscr.getmaxyx()
    stdscr.addnstr(0,0,'── 内容プレビュー(任意キーで戻る)──',w-1,curses.A_BOLD)
    r=1
    try:
        for l in open(f,encoding='utf-8',errors='replace'):
            if r>=h-1: break
            if not l.strip(): continue
            try:o=json.loads(l)
            except:continue
            role=(o.get('message') or {}).get('role')
            if role not in ('user','assistant'): continue
            t=msgtext(o)
            if not t: continue
            t=re.sub(r'\s+',' ',t).strip()
            stdscr.addnstr(r,0,'[%s] %s'%(role,t),w-1, curses.color_pair(2) if role=='user' else 0); r+=1
    except Exception: pass
    stdscr.refresh(); stdscr.getch()
def run(stdscr):
    curses.curs_set(0); curses.use_default_colors()
    for i,c in enumerate(PAL): curses.init_pair(i+1,c,-1)
    try: curses.mousemask(curses.ALL_MOUSE_EVENTS|curses.REPORT_MOUSE_POSITION)
    except Exception: pass
    ti=0;sel=0;top=0;search=''
    files=tabfiles(ti,search)
    while True:
        h,w=stdscr.getmaxyx(); rows=max(3,h-4)
        if sel>=len(files): sel=max(0,len(files)-1)
        if sel<0: sel=0
        if sel<top: top=sel
        if sel>=top+rows: top=sel-rows+1
        if top<0: top=0
        stdscr.erase()
        x=0
        for i,t in enumerate(TABS):
            lbl='  %s  '%t
            stdscr.addnstr(0,x,lbl,w-1-x, curses.A_REVERSE if i==ti else curses.A_DIM); x+=len(lbl)+1
        stdscr.addnstr(1,0,'─'*(w-1),w-1,curses.A_DIM)
        total=len(files); page=top//rows+1; pages=max(1,(total+rows-1)//rows)
        stdscr.addnstr(2,0,'  履歴を選んで Enter で続きから   ページ %d/%d ・ 全 %d 件%s'%(page,pages,total,('  検索『%s』'%search if search else '')),w-1,curses.A_DIM)
        tw=max(20,w-42)
        for r in range(rows):
            idx=top+r
            if idx>=total: continue
            sid,dev,ttl,msgs,mt=scan(files[idx])
            line='%s %-*s  %7s  %4dmsg  %-12s'%('❯' if idx==sel else ' ',tw,disp(ttl,tw),reltime(mt),msgs,dev[:12])
            attr=curses.A_REVERSE if idx==sel else curses.color_pair(cp(dev))
            try: stdscr.addnstr(3+r,0,line,w-1,attr)
            except curses.error: pass
        stdscr.addnstr(h-1,0,'  ↑↓ 選択   ←→ タブ   PgUp/PgDn ページ   Enter 再開   Space 内容   / 検索   q 終了',w-1,curses.A_DIM)
        stdscr.refresh()
        c=stdscr.getch()
        if c in (ord('q'),27): return None
        elif c==curses.KEY_UP: sel-=1
        elif c==curses.KEY_DOWN: sel+=1
        elif c==curses.KEY_LEFT: ti=(ti-1)%len(TABS);sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_RIGHT: ti=(ti+1)%len(TABS);sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_NPAGE: sel=min(total-1,top+rows);top=sel
        elif c==curses.KEY_PPAGE: top=max(0,top-rows);sel=top
        elif c==ord(' '):
            if files: preview(stdscr,files[sel])
        elif c in (curses.KEY_ENTER,10,13):
            if files: return files[sel]
        elif c==ord('/'):
            curses.echo();curses.curs_set(1); stdscr.addnstr(h-1,0,'検索: '+' '*(w-7),w-1); stdscr.move(h-1,4)
            try: search=stdscr.getstr(h-1,4,60).decode('utf-8','replace').strip()
            except Exception: search=''
            curses.noecho();curses.curs_set(0);sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_MOUSE:
            try:
                _,mx,my,_,bs=curses.getmouse()
                if bs & curses.BUTTON4_PRESSED: sel=max(0,sel-3)
                elif hasattr(curses,'BUTTON5_PRESSED') and (bs & curses.BUTTON5_PRESSED): sel=min(total-1,sel+3)
                elif bs & curses.BUTTON1_CLICKED:
                    rr=my-3
                    if 0<=rr<rows and top+rr<total: sel=top+rr; return files[sel]
            except Exception: pass
res=None
try: res=curses.wrapper(run)
except Exception: res=None
if res:
    sid=os.path.splitext(os.path.basename(res))[0]
    open(os.environ['RESULTFILE'],'w',encoding='utf-8').write(res+'\t'+sid)
PYEOF
sel="$(cat "$RF" 2>/dev/null)"; rm -f "$RF"
[[ -z "$sel" ]] && exit 0
file="${sel%%$'\t'*}"; sid="${sel##*$'\t'}"
encd="$(printf '%s' "$(pwd)" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$PROJECTS/$encd"
dest="$PROJECTS/$encd/$sid.jsonl"; [[ "$file" != "$dest" ]] && cp "$file" "$dest"
exec command claude --resume "$sid"
