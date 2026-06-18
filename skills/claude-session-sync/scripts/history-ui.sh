#!/usr/bin/env bash
#  claude-session-sync : 履歴ブラウザ UI (macOS / Linux)  —  `claude -h` から起動
#  公式 `claude --resume` 風。上部に枠付き検索ボックス(入力で即フィルタ)＋タブ＋デバイス列。各項目=2行＋区切り線。
#  python curses。 文字入力=検索 Backspace=消去 Esc=クリア/終了 ↑↓選択 ←→タブ PgUp/PgDn頁 Enter再開 Space内容。マウス対応。
set -uo pipefail
PY="$(command -v python3 || command -v python || true)"; [[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
SHARE="$(get share)"; RF="$(mktemp)"
RESULTFILE="$RF" PROJECTS="$PROJECTS" SHARE="$SHARE" CWDP="$(pwd)" "$PY" - <<'PYEOF'
import curses,os,json,glob,re,time,unicodedata
root=os.environ['PROJECTS']; share=os.environ.get('SHARE',''); cwdp=os.environ.get('CWDP','')
def dispw(s):
    w=0
    for ch in s:
        o=ord(ch)
        if unicodedata.east_asian_width(ch) in ('W','F') or 0x1F300<=o<=0x1FAFF: w+=2
        else: w+=1
    return w
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
# 共有先が無い場合のローカル titles.map(自動タイトル)。共有先の値があればそちら優先。
for _k,_v in load_map(os.path.join(os.path.dirname(root),'sessions','titles.map')).items(): titlemap.setdefault(_k,_v)
def all_sessions():
    fs=[]
    for f in glob.glob(os.path.join(root,'**','*.jsonl'),recursive=True):
        d=os.path.basename(os.path.dirname(f)); b=os.path.splitext(os.path.basename(f))[0]
        if d=='subagents' or d.startswith('wf_') or 'session-sync-titlegen' in d or b.startswith('agent-') or b=='journal': continue
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
    cwd='';prev='';ai='';msgs=0;cap=4000;n=0;more=False
    try:
        for l in open(f,encoding='utf-8',errors='replace'):
            if n>=cap: more=True; break
            n+=1
            if '"type":"user"' in l or '"type":"assistant"' in l: msgs+=1
            if cwd and ai and prev: continue
            if '"cwd"' in l or 'ai-title' in l or '"role":"user"' in l:
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
    proj=os.path.basename(os.path.dirname(f))
    msgsstr=str(msgs)+('+' if more else '')
    r=(sid,dev,ttl,msgsstr,os.path.getmtime(f),proj); cache[f]=r; return r
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
def disp(s,n): return s if len(s)<=n else (s[:n-1]+'…')
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
        h,w=stdscr.getmaxyx(); rows=max(2,(h-7)//3); boxw=min(w-2,56)
        if sel>=len(files): sel=max(0,len(files)-1)
        if sel<0: sel=0
        if sel<top: top=sel
        if sel>=top+rows: top=sel-rows+1
        if top<0: top=0
        stdscr.erase()
        # 検索ボックス(枠付き)
        lab='─ 🔍 検索 '
        stdscr.addnstr(0,0,'┌'+lab+'─'*max(0,boxw-dispw(lab))+'┐',w-1,curses.A_DIM)
        inner=search+'█'; pad=max(0,boxw-1-dispw(inner))
        stdscr.addnstr(1,0,'│ '+inner+' '*pad+'│',w-1)
        stdscr.addnstr(2,0,'└'+'─'*boxw+'┘',w-1,curses.A_DIM)
        # タブ
        x=0
        for i,t in enumerate(TABS):
            l=' %s '%t
            stdscr.addnstr(3,x,l,max(1,w-1-x), curses.A_REVERSE if i==ti else curses.A_DIM); x+=len(l)+2
        total=len(files); page=top//rows+1; pages=max(1,(total+rows-1)//rows)
        stdscr.addnstr(4,0,'Enter で続きから   ページ %d/%d ・ 全 %d 件'%(page,pages,total),w-1,curses.A_DIM)
        stdscr.addnstr(5,1,'─'*(w-2),w-1,curses.A_DIM)
        for r in range(rows):
            idx=top+r
            if idx>=total: break
            sid,dev,ttl,msgs,mt,proj=scan(files[idx])
            base=6+r*3
            if base+2>h-2: break
            stdscr.addnstr(base,0,('❯ ' if idx==sel else '  ')+disp(ttl,w-3),w-1, curses.A_REVERSE if idx==sel else curses.A_BOLD)
            dshow=dev[:14]
            stdscr.addnstr(base+1,3,dshow,max(1,w-4),curses.color_pair(cp(dev)))
            stdscr.addnstr(base+1,3+len(dshow),' │ %s msg │ %s │ %s'%(msgs,reltime(mt),proj[:20]),max(1,w-1),curses.A_DIM)
            stdscr.addnstr(base+2,1,'─'*(w-2),w-1,curses.A_DIM)
        stdscr.addnstr(h-1,0,'文字=検索 Backspace=消去 Esc=クリア/終了 ↑↓選択 ←→タブ Enter再開 Space内容',w-1,curses.A_DIM)
        stdscr.refresh()
        c=stdscr.getch()
        if c==27:
            if search: search='';sel=0;top=0;files=tabfiles(ti,search)
            else: return None
        elif c in (curses.KEY_BACKSPACE,127,8):
            if search: search=search[:-1];sel=0;top=0;files=tabfiles(ti,search)
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
        elif c==curses.KEY_MOUSE:
            try:
                _,mx,my,_,bs=curses.getmouse()
                if bs & curses.BUTTON4_PRESSED: sel=max(0,sel-3)
                elif hasattr(curses,'BUTTON5_PRESSED') and (bs & curses.BUTTON5_PRESSED): sel=min(total-1,sel+3)
                elif bs & curses.BUTTON1_CLICKED:
                    rr=my-6
                    if rr>=0 and rr//3<rows and top+rr//3<total: sel=top+rr//3; return files[sel]
            except Exception: pass
        elif 33<=c<=126:
            search+=chr(c);sel=0;top=0;files=tabfiles(ti,search)
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
