#!/usr/bin/env bash
#  claude-session-sync : 履歴ブラウザ UI (macOS / Linux)  —  `claude -h` から起動
#  公式 `claude --resume` 風。上部に枠付き検索ボックス(入力で即フィルタ)＋タブ([全履歴=メイン+サブ全部][このプロジェクト][お気に入り][メインエージェント][サブエージェント])＋デバイス列。各項目=2行＋区切り線。
#  サブエージェント=サブエージェント履歴(実行元メイン会話/実行元デバイス/実行中を表示)。メイン行はロック無し+サブエージェント実行中のとき実行中デバイスを表示。
#  python curses。 文字入力=検索 Backspace=消去 Esc=クリア/終了 ↑↓選択 ←→タブ PgUp/PgDn頁 Ctrl+G頁番号ジャンプ Enter再開 Space内容 Tab=操作メニュー。マウス対応(行/ページ切替ボタン/番号クリック)。
set -uo pipefail
PY="$(command -v python3 || command -v python || true)"; [[ -n "$PY" ]] || { echo "python3 が必要です。" >&2; exit 1; }
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
[[ -d "$PROJECTS" ]] || { echo "履歴フォルダがありません: $PROJECTS" >&2; exit 1; }
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
SHARE="$(get share)"; RF="$(mktemp)"; SUBWIN="$(get subRunWin)"
RESULTFILE="$RF" PROJECTS="$PROJECTS" SHARE="$SHARE" CWDP="$(pwd)" SELFMACHINE="$(hostname)" SUBWIN="$SUBWIN" "$PY" - <<'PYEOF'
import curses,os,json,glob,re,time,unicodedata
root=os.environ['PROJECTS']; share=os.environ.get('SHARE',''); cwdp=os.environ.get('CWDP',''); selfm=os.environ.get('SELFMACHINE','')
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
# お気に入り(sid の集合)。共有先 + ローカルの和集合で読み込み、保存は両方へ書く。
favs=set()
fav_local=os.path.join(os.path.dirname(root),'sessions','favorites.txt')
fav_share=os.path.join(share,'sessions','favorites.txt') if share else None
for _fp in (fav_share,fav_local):
    if _fp and os.path.exists(_fp):
        for _l in open(_fp,encoding='utf-8',errors='replace'):
            _s=_l.strip()
            if _s: favs.add(_s)
def save_favs():
    content='\n'.join(sorted(favs))+'\n'
    for tp in dict.fromkeys([x for x in (fav_share,fav_local) if x]):
        try:
            os.makedirs(os.path.dirname(tp),exist_ok=True)
            open(tp,'w',encoding='utf-8').write(content)
        except Exception: pass
def toggle_fav(sid):
    favs.discard(sid) if sid in favs else favs.add(sid)
    save_favs()
def load_locks():
    # 使用中(アクセス中)の会話: 共有 locks/*.lock の session=<sid>(12h超は残骸として無視)。sid->machine。
    h={}
    if not share: return h
    ld=os.path.join(share,'locks')
    if not os.path.isdir(ld): return h
    now=time.time()
    for lf in glob.glob(os.path.join(ld,'*.lock')):
        try:
            if now-os.path.getmtime(lf)>43200: continue
            c=open(lf,encoding='utf-8',errors='replace').read()
        except Exception: continue
        ms=re.search(r'session=([^\s]+)',c)
        if ms and ms.group(1) and ms.group(1)!='-':
            mm=re.search(r'machine=([^\s]+)',c)
            h[ms.group(1)]=mm.group(1) if mm else '?'
    return h
INUSE=load_locks()
def build_context(f):
    firstu=[]; tail=[]
    try:
        for l in open(f,encoding='utf-8',errors='replace'):
            if '"role":"user"' not in l and '"role":"assistant"' not in l: continue
            try:o=json.loads(l)
            except:continue
            role=(o.get('message') or {}).get('role')
            if role not in ('user','assistant'): continue
            t=msgtext(o)
            if not t: continue
            t=re.sub(r'\s+',' ',t).strip()
            if not t: continue
            t=t[:500]
            if role=='user' and len(firstu)<3: firstu.append('- '+t)
            tail.append(('%s: '%role)+t)
            if len(tail)>12: tail=tail[1:]
    except Exception: pass
    parts=['以下は引き継ぎ元の会話の文脈です。これを踏まえてユーザーを支援してください。']
    if firstu: parts+=['','## 最初の要望']+firstu
    parts+=['','## 直近のやり取り']+tail
    return '\n'.join(parts)[:6000]
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
# プロジェクトキー(符号化cwd 例 C--Users-Minikuma / -Users-clark)からデバイス名を推定(devices.map に無い時の保険)。
def dev_from_key(k):
    if not k: return 'unknown'
    m=re.match(r'^[A-Za-z]--Users-([A-Za-z0-9]+)',k)
    if m: return 'Win/'+m.group(1)
    m=re.match(r'^-Users-([A-Za-z0-9]+)',k)
    if m: return 'Mac/'+m.group(1)
    m=re.match(r'^-home-([A-Za-z0-9]+)',k)
    if m: return 'Linux/'+m.group(1)
    if k.startswith('-root'): return 'Linux/root'
    return 'unknown'
# サブエージェント履歴: <mainSid>/subagents/agent-*.jsonl。親IDは祖父フォルダ名から取得(読み込み不要)。
def sub_agents():
    fs=[f for f in glob.glob(os.path.join(root,'**','agent-*.jsonl'),recursive=True) if os.path.basename(os.path.dirname(f))=='subagents']
    fs.sort(key=lambda p: os.path.getmtime(p), reverse=True); return fs
def sub_parent_sid(f): return os.path.basename(os.path.dirname(os.path.dirname(f)))
def sub_proj_key(f): return os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(f))))
# サブエージェント transcript の走査(種別=attributionAgent / タイトル=最初の依頼文 / 実行元デバイス)。
def scan_sub(f):
    if f in cache: return cache[f]
    atype='';first='';msgs=0;cwd='';cap=2000;n=0;more=False
    try:
        for l in open(f,encoding='utf-8',errors='replace'):
            if n>=cap: more=True; break
            n+=1
            if '"type":"user"' in l or '"type":"assistant"' in l: msgs+=1
            if atype and first and cwd: continue
            if 'attributionAgent' in l or '"role":"user"' in l or '"cwd"' in l:
                try:o=json.loads(l)
                except:continue
                if not atype and o.get('attributionAgent'): atype=str(o['attributionAgent'])
                if not cwd and o.get('cwd'): cwd=str(o['cwd'])
                if not first and (o.get('message') or {}).get('role')=='user':
                    t=msgtext(o)
                    if t: first=re.sub(r'\s+',' ',t).strip()
    except Exception: pass
    psid=sub_parent_sid(f)
    if not atype: atype='subagent'
    dev=devmap.get(psid) or (dev_from_cwd(cwd) if cwd else dev_from_key(sub_proj_key(f)))
    ttl=first or ('('+atype+')')
    proj=os.path.basename(os.path.dirname(f)); msgsstr=str(msgs)+('+' if more else '')
    r=(os.path.splitext(os.path.basename(f))[0],dev,ttl,msgsstr,os.path.getmtime(f),proj,psid,atype); cache[f]=r; return r
# 自端末判定: ロックは hostname、パス由来は Mac/<user> 形式なので両方で照合。
def is_self_dev(d): return bool(d) and (d==selfm or d==selfalt)
# 実行中サブエージェント検知: agent-*.jsonl の更新が直近 subwin 秒以内なら実行中とみなす(公式ロックが無いため鮮度で近似)。
# parentSid -> [device,count,mtime]。5秒キャッシュで毎フレーム再走査を避ける。
_runs={'t':0.0,'v':{}}
def load_runsubs():
    nt=time.time()
    if _runs['t']>0 and nt-_runs['t']<5: return _runs['v']
    h={}
    for f in SUBALL:
        try: mt=os.path.getmtime(f)
        except Exception: continue
        if nt-mt>subwin: continue
        psid=sub_parent_sid(f); dev=devmap.get(psid) or dev_from_key(sub_proj_key(f))
        if psid in h:
            e=h[psid]; e[1]+=1
            if mt>e[2]: e[0]=dev; e[2]=mt
        else: h[psid]=[dev,1,mt]
    _runs['t']=nt; _runs['v']=h; return h
ALL=all_sessions(); SUBALL=sub_agents(); now=time.time()
_sw=(os.environ.get('SUBWIN') or '').strip(); subwin=int(_sw) if _sw.isdigit() else 120
selfalt=dev_from_cwd(os.path.expanduser('~'))   # 自端末のパス由来名(例 Mac/clark)。「（このデバイス）」照合用。
# 全履歴=メイン+サブ全部(時系列)、このプロジェクト/お気に入り/メインエージェント=メイン、サブエージェント=サブ。
TABS=['全履歴','このプロジェクト','お気に入り','メインエージェント','サブエージェント']
ALLTAB=0; SUBTAB=4
def is_sub_file(f): return os.path.basename(os.path.dirname(f))=='subagents'
def tabfiles(ti,search):
    if ti==SUBTAB: fs=list(SUBALL)
    elif ti==ALLTAB: fs=sorted(ALL+SUBALL, key=lambda p: os.path.getmtime(p), reverse=True)
    elif ti==1: fs=[f for f in ALL if os.path.basename(os.path.dirname(f))==cwdkey]
    elif ti==2: fs=[f for f in ALL if os.path.splitext(os.path.basename(f))[0] in favs]
    else: fs=list(ALL)
    if search:
        s=search.lower()
        if ti==SUBTAB:
            fs=[f for f in fs if s in sub_parent_sid(f).lower() or (f in cache and s in cache[f][2].lower())]
        else:
            fs=[f for f in fs if s in os.path.basename(os.path.dirname(f)).lower() or s in os.path.basename(f).lower() or (f in cache and s in cache[f][2].lower())]
    # 同一会話(同 sid)が複数フォルダに在る場合は重複排除し最新だけ残す(一覧は mtime 降順=先頭が最新)。
    seen=set(); out=[]
    for f in fs:
        b=os.path.splitext(os.path.basename(f))[0]
        if b in seen: continue
        seen.add(b); out.append(f)
    return out
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
    stdscr.refresh()
    while stdscr.getch()==-1: pass
def action_menu(stdscr,sid,ttl):
    # 戻り値: resume / fork / newctx / fav / preview / back
    stdscr.erase(); h,w=stdscr.getmaxyx()
    favtxt='から外す' if sid in favs else 'に追加'
    lines=['操作: '+ttl,'',
           '  [Enter] 続きから (このフォルダで再開)',
           '  [f]     ★ お気に入り'+favtxt,
           '  [k]     フォーク (複製して別の分岐で続ける・元は変更しない)',
           '  [n]     文脈を引き継いで新しい会話を始める',
           '  [r]     権限を変えて再開 (plan〜完全フリー)',
           '  [p]     内容プレビュー',
           '  [Esc]   戻る']
    for i,ln in enumerate(lines):
        if i>=h-1: break
        stdscr.addnstr(i,0,ln,w-1, curses.A_BOLD if i==0 else 0)
    stdscr.refresh()
    while True:
        c=stdscr.getch()
        if c in (curses.KEY_ENTER,10,13): return 'resume'
        if c==27: return 'back'
        if c in (ord('f'),ord('F')): return 'fav'
        if c in (ord('k'),ord('K')): return 'fork'
        if c in (ord('n'),ord('N')): return 'newctx'
        if c in (ord('r'),ord('R')): return 'perm'
        if c in (ord('p'),ord('P'),ord(' ')): return 'preview'
def sub_menu(stdscr,si):
    # サブエージェント行の操作(戻り値: openparent / preview / back)。サブ自体は再開単位ではないので親を開く。
    sid,dev,ttl,msgs,mt,proj,psid,atype=si
    pt=titlemap.get(psid) or psid; running=(time.time()-mt<=subwin)
    stdscr.erase(); h,w=stdscr.getmaxyx()
    lines=['サブエージェント: '+ttl,
           '  種別: %s    実行元デバイス: %s'%(atype,dev),
           '  実行元メイン: %s%s'%(pt,'  ← 現在このメインから実行中' if running else ''),
           '',
           '  [Enter] 実行元のメイン会話を開く',
           '  [p]     内容プレビュー',
           '  [Esc]   戻る']
    for i,ln in enumerate(lines):
        if i>=h-1: break
        stdscr.addnstr(i,0,ln,w-1,curses.A_BOLD if i==0 else 0)
    stdscr.refresh()
    while True:
        c=stdscr.getch()
        if c in (curses.KEY_ENTER,10,13): return 'openparent'
        if c==27: return 'back'
        if c in (ord('p'),ord('P'),ord(' ')): return 'preview'
def pick_page(stdscr,pages):
    # ページ番号ジャンプ入力(戻り値: 1..pages / 取消は None)。Ctrl+G または ページ番号クリックで開く。
    if pages<=1: return None
    buf=''
    while True:
        stdscr.erase(); h,w=stdscr.getmaxyx()
        stdscr.addnstr(0,0,'ページ番号へジャンプ',w-1,curses.A_BOLD)
        stdscr.addnstr(2,0,'ページ番号 (1-%d): %s█'%(pages,buf),w-1)
        stdscr.addnstr(4,0,'数字=入力  Backspace=消去  Enter=決定  Esc=取消',w-1,curses.A_DIM)
        stdscr.refresh(); c=stdscr.getch()
        if c==27: return None
        elif c in (curses.KEY_ENTER,10,13):
            if buf:
                n=int(buf)
                if 1<=n<=pages: return n
                buf=''
        elif c in (curses.KEY_BACKSPACE,127,8): buf=buf[:-1]
        elif 48<=c<=57 and len(buf)<6: buf+=chr(c)
def perm_menu(stdscr):
    opts=[('default','既定(都度確認)'),('plan','プラン(読取中心・安全)'),('acceptEdits','編集を自動承認'),('auto','自動(オート)'),('dontAsk','確認しない'),('bypassPermissions','⚠ 権限バイパス'),('full','⚠⚠ 完全フリー(全回避・env取得/コピー可)')]
    sel=0
    while True:
        stdscr.erase(); h,w=stdscr.getmaxyx()
        stdscr.addnstr(0,0,'この起動で使う権限を選ぶ  (Up/Down, Enter, Esc)',w-1,curses.A_BOLD)
        for i,(v,l) in enumerate(opts):
            if i+2>=h-1: break
            stdscr.addnstr(i+2,0,('> ' if i==sel else '  ')+l,w-1, curses.A_REVERSE if i==sel else 0)
        stdscr.refresh(); c=stdscr.getch()
        if c==27: return None
        elif c==curses.KEY_UP: sel=max(0,sel-1)
        elif c==curses.KEY_DOWN: sel=min(len(opts)-1,sel+1)
        elif c in (curses.KEY_ENTER,10,13):
            v=opts[sel][0]
            if v in ('bypassPermissions','full'):
                stdscr.erase(); stdscr.addnstr(0,0,'⚠ 上位権限の確認',w-1,curses.A_BOLD)
                warn='完全フリーは全権限チェックを回避し env 取得・コピー・任意実行まで無確認で許可します。' if v=='full' else '権限バイパスはプロンプトなしでツールを実行します。'
                stdscr.addnstr(2,0,warn,w-1); stdscr.addnstr(4,0,'本当にこの権限で起動しますか? (y/N)',w-1); stdscr.refresh()
                a=-1
                while a==-1: a=stdscr.getch()
                if a in (ord('y'),ord('Y')): return v
                else: continue
            return v
def block_inuse(stdscr,sid):
    # 使用中(アクセス中)なら警告して中止(True=中止)。f で強行(False)。
    inuse=load_locks()
    if sid not in inuse: return False
    m=inuse[sid]; isself=(m==selfm); stdscr.erase(); h,w=stdscr.getmaxyx()
    stdscr.addnstr(0,0,'⚠ この会話は現在アクセス中(使用中)です',w-1,curses.A_BOLD)
    stdscr.addnstr(2,0,'使用中のデバイス: '+m+('（このデバイス）' if isself else ''),w-1)
    stdscr.addnstr(3,0,'同時に開くと履歴が壊れる(.sync-conflict)恐れがあります。',w-1)
    stdscr.addnstr(4,0,('このデバイスの別ウィンドウ/タブで開いています。そちらを終了してから開き直してください。' if isself else '先にそのデバイス側でこの会話を終了(切断)してから開き直してください。'),w-1)
    stdscr.addnstr(6,0,'任意キーで戻る   /   f = それでも開く(危険)',w-1,curses.A_DIM)
    stdscr.refresh()
    c=-1
    while c==-1: c=stdscr.getch()
    return not (c in (ord('f'),ord('F')))
def run(stdscr):
    curses.curs_set(0); curses.use_default_colors()
    for i,c in enumerate(PAL): curses.init_pair(i+1,c,-1)
    try: curses.mousemask(curses.ALL_MOUSE_EVENTS|curses.REPORT_MOUSE_POSITION)
    except Exception: pass
    stdscr.timeout(1500)   # 1.5秒ごとに再描画(getch が -1 を返す)→「アクセス中」をライブ更新
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
        # ページ切替ボタン(クリック可)＋番号ジャンプ。ボタンの桁範囲を記録しマウスで判定。
        seg_enter='Enter=続き   '; seg_prev=' < 前 '; seg_mid='  ページ %d/%d (全 %d件)  '%(page,pages,total); seg_next=' 次 > '; seg_hint='   PgUp/PgDn ・ Ctrl+G=番号'
        px=0
        stdscr.addnstr(4,px,seg_enter,max(1,w-1),curses.A_DIM); px+=len(seg_enter)
        btn_prev=(px,px+len(seg_prev)); stdscr.addnstr(4,px,seg_prev,max(1,w-1-px), curses.A_REVERSE if page>1 else curses.A_DIM); px+=len(seg_prev)
        btn_jump=(px,px+len(seg_mid)); stdscr.addnstr(4,px,seg_mid,max(1,w-1-px),0); px+=len(seg_mid)
        btn_next=(px,px+len(seg_next)); stdscr.addnstr(4,px,seg_next,max(1,w-1-px), curses.A_REVERSE if page<pages else curses.A_DIM); px+=len(seg_next)
        stdscr.addnstr(4,px,seg_hint,max(1,w-1-px),curses.A_DIM)
        stdscr.addnstr(5,1,'─'*(w-2),w-1,curses.A_DIM)
        inuse=load_locks(); runs=load_runsubs(); nowt=time.time()
        for r in range(rows):
            idx=top+r
            if idx>=total: break
            base=6+r*3
            if base+2>h-2: break
            if is_sub_file(files[idx]):
                # サブエージェント行: 🤖種別 + 実行元メイン会話 + 実行元デバイス + 実行中状態
                sid,dev,ttl,msgs,mt,proj,psid,atype=scan_sub(files[idx])
                stdscr.addnstr(base,0,('❯ ' if idx==sel else '  ')+disp(ttl,max(4,w-3)),w-1, curses.A_REVERSE if idx==sel else curses.A_BOLD)
                head='🤖'+atype; dshow=head[:16]
                stdscr.addnstr(base+1,3,dshow,max(1,w-4),curses.color_pair(cp(atype)))
                metabase=' │ %s msg │ %s │ %s'%(msgs,reltime(mt),proj[:20])
                running=(nowt-mt<=subwin); pt=disp(titlemap.get(psid) or '(無題のメイン)',24)
                selfm2=('（このデバイス）' if is_self_dev(dev) else '')
                if running: mark='  [実行中 ← 「%s」メインから ・ 実行元: %s%s]'%(pt,dev,selfm2)
                else: mark='  [元: 「%s」 ・ %s]'%(pt,dev)
                markattr=curses.color_pair(3) if running else curses.A_DIM
            else:
                sid,dev,ttl,msgs,mt,proj=scan(files[idx])
                star='★ ' if sid in favs else ''
                stdscr.addnstr(base,0,('❯ ' if idx==sel else '  ')+star+disp(ttl,max(4,w-3-len(star)*2)),w-1, curses.A_REVERSE if idx==sel else curses.A_BOLD)
                dshow=dev[:14]
                stdscr.addnstr(base+1,3,dshow,max(1,w-4),curses.color_pair(cp(dev)))
                metabase=' │ %s msg │ %s │ %s'%(msgs,reltime(mt),proj[:20]); mark=''; markattr=curses.A_DIM
                if sid in inuse:
                    mark='  [アクセス中: '+inuse[sid]+('（このデバイス）' if is_self_dev(inuse[sid]) else '')+']'; markattr=curses.color_pair(6)
                elif runs and sid in runs:
                    rd,cnt,_=runs[sid]; cs=('（×%d）'%cnt) if cnt>1 else ''
                    mark='  [%s でサブエージェント実行中%s%s]'%(rd,cs,'（このデバイス）' if is_self_dev(rd) else ''); markattr=curses.color_pair(3)
            stdscr.addnstr(base+1,3+len(dshow),metabase,max(1,w-1),curses.A_DIM)
            if mark: stdscr.addnstr(base+1,min(w-2,3+len(dshow)+len(metabase)),mark,max(1,w-1),markattr)
            stdscr.addnstr(base+2,1,'─'*(w-2),w-1,curses.A_DIM)
        stdscr.addnstr(h-1,0,'文字=検索 ↑↓選択 ←→タブ Enter再開 Tab=操作 Space内容 PgUp/PgDn=頁 Ctrl+G=頁番号 Esc終了',w-1,curses.A_DIM)
        stdscr.refresh()
        c=stdscr.getch()
        if c==-1: continue   # タイムアウト(入力なし)→ 再描画してアクセス中を最新化
        if c==27:
            if search: search='';sel=0;top=0;files=tabfiles(ti,search)
            else: return None
        elif c==9:  # Tab: 操作メニュー
            if files and is_sub_file(files[sel]):
                si=scan_sub(files[sel]); act=sub_menu(stdscr,si)
                if act=='openparent':
                    psid=si[6]; pf=next((f for f in ALL if os.path.splitext(os.path.basename(f))[0]==psid),None)
                    if pf:
                        if not block_inuse(stdscr,psid): return ('resume',pf)
                    else: preview(stdscr,files[sel])
                elif act=='preview': preview(stdscr,files[sel])
            elif files:
                fsid=os.path.splitext(os.path.basename(files[sel]))[0]
                fttl=scan(files[sel])[2]
                act=action_menu(stdscr,fsid,fttl)
                if act=='resume':
                    if not block_inuse(stdscr,fsid): return ('resume',files[sel])
                elif act=='fork':
                    if not block_inuse(stdscr,fsid): return ('fork',files[sel])
                elif act=='newctx': return ('newctx',files[sel])
                elif act=='perm':
                    p=perm_menu(stdscr)
                    if p and not block_inuse(stdscr,fsid): return ('perm:'+p,files[sel])
                elif act=='fav':
                    toggle_fav(fsid)
                    if TABS[ti]=='お気に入り':
                        files=tabfiles(ti,search)
                        if sel>=len(files): sel=max(0,len(files)-1)
                elif act=='preview': preview(stdscr,files[sel])
        elif c in (curses.KEY_BACKSPACE,127,8):
            if search: search=search[:-1];sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_UP: sel-=1
        elif c==curses.KEY_DOWN: sel+=1
        elif c==curses.KEY_LEFT: ti=(ti-1)%len(TABS);sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_RIGHT: ti=(ti+1)%len(TABS);sel=0;top=0;files=tabfiles(ti,search)
        elif c==curses.KEY_NPAGE: sel=min(total-1,top+rows);top=sel
        elif c==curses.KEY_PPAGE: top=max(0,top-rows);sel=top
        elif c==7:  # Ctrl+G: ページ番号ジャンプ
            pg=pick_page(stdscr,pages)
            if pg: top=(pg-1)*rows; sel=top
        elif c==ord(' '):
            if files: preview(stdscr,files[sel])
        elif c in (curses.KEY_ENTER,10,13):
            if files and is_sub_file(files[sel]):
                psid=sub_parent_sid(files[sel]); pf=next((f for f in ALL if os.path.splitext(os.path.basename(f))[0]==psid),None)
                if pf:
                    if not block_inuse(stdscr,psid): return ('resume',pf)
                else: preview(stdscr,files[sel])
            elif files and not block_inuse(stdscr,os.path.splitext(os.path.basename(files[sel]))[0]): return ('resume',files[sel])
        elif c==curses.KEY_MOUSE:
            try:
                _,mx,my,_,bs=curses.getmouse()
                if bs & curses.BUTTON4_PRESSED: sel=max(0,sel-3)
                elif hasattr(curses,'BUTTON5_PRESSED') and (bs & curses.BUTTON5_PRESSED): sel=min(total-1,sel+3)
                elif bs & curses.BUTTON1_CLICKED:
                    if my==4:   # ページ切替ボタン/番号ジャンプの行
                        if btn_prev[0]<=mx<btn_prev[1] and page>1: top=max(0,top-rows); sel=top
                        elif btn_next[0]<=mx<btn_next[1] and page<pages: sel=min(total-1,top+rows); top=sel
                        elif btn_jump[0]<=mx<btn_jump[1] and pages>1:
                            pg=pick_page(stdscr,pages)
                            if pg: top=(pg-1)*rows; sel=top
                    else:
                        rr=my-6
                        if rr>=0 and rr//3<rows and top+rr//3<total:
                            sel=top+rr//3
                            if is_sub_file(files[sel]):
                                psid=sub_parent_sid(files[sel]); pf=next((f for f in ALL if os.path.splitext(os.path.basename(f))[0]==psid),None)
                                if pf and not block_inuse(stdscr,psid): return ('resume',pf)
                            elif not block_inuse(stdscr,os.path.splitext(os.path.basename(files[sel]))[0]): return ('resume',files[sel])
            except Exception: pass
        elif 33<=c<=126:
            search+=chr(c);sel=0;top=0;files=tabfiles(ti,search)
res=None
try: res=curses.wrapper(run)
except Exception: res=None
if res:
    action,fpath=res
    sid=os.path.splitext(os.path.basename(fpath))[0]
    rf=os.environ['RESULTFILE']
    if action=='newctx':
        open(rf+'.ctx','w',encoding='utf-8').write(build_context(fpath))
    open(rf,'w',encoding='utf-8').write(action+'\t'+fpath+'\t'+sid)
PYEOF
sel="$(cat "$RF" 2>/dev/null)"
if [[ -z "$sel" ]]; then rm -f "$RF" "$RF.ctx"; exit 0; fi
action="$(printf '%s' "$sel" | cut -f1)"; file="$(printf '%s' "$sel" | cut -f2)"; sid="$(printf '%s' "$sel" | cut -f3)"
if [[ "$action" == "newctx" ]]; then
  ctx="$(cat "$RF.ctx" 2>/dev/null)"; rm -f "$RF" "$RF.ctx"
  exec command claude --append-system-prompt "$ctx"
fi
rm -f "$RF" "$RF.ctx"
permflag=()
case "$action" in
  perm:*) p="${action#perm:}"
    case "$p" in
      full) permflag=(--dangerously-skip-permissions);;
      plan|acceptEdits|auto|dontAsk|bypassPermissions) permflag=(--permission-mode "$p");;
    esac
    action=resume;;
esac
# --- 前回の model/effort/permission を引き継ぐ(launchopts.map=フックが起動時に記録) ---
inherit=(); optline=""
for lf in "$SHARE/sessions/launchopts.map" "$CLAUDE/sessions/launchopts.map"; do
  [ -f "$lf" ] || continue
  l="$(grep -F "$sid"$'\t' "$lf" 2>/dev/null | tail -n1)"; [ -n "$l" ] && { optline="$l"; break; }
done
im="$(printf '%s' "$optline" | cut -f2)"; ie="$(printf '%s' "$optline" | cut -f3)"; ip="$(printf '%s' "$optline" | cut -f4)"
[ -z "$im" ] && im="$(tail -n 400 "$file" 2>/dev/null | grep -oE '"model"[[:space:]]*:[[:space:]]*"claude[^"]*"' | tail -n1 | sed -E 's/.*"(claude[^"]*)".*/\1/')"
[ -n "$im" ] && inherit+=(--model "$im")
[ -n "$ie" ] && inherit+=(--effort "$ie")
if [ ${#permflag[@]} -eq 0 ]; then
  case "$ip" in
    full) permflag=(--dangerously-skip-permissions);;
    plan|acceptEdits|auto|dontAsk|bypassPermissions) permflag=(--permission-mode "$ip");;
  esac
fi
export CSS_LAUNCH_MODEL="$im" CSS_LAUNCH_EFFORT="$ie" CSS_LAUNCH_PERM="$ip"
encd="$(printf '%s' "$(pwd)" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$PROJECTS/$encd"
dest="$PROJECTS/$encd/$sid.jsonl"; [[ "$file" != "$dest" ]] && cp "$file" "$dest"
final=(--resume "$sid")
[[ "$action" == "fork" ]] && final+=(--fork-session)
[ ${#inherit[@]} -gt 0 ] && final+=("${inherit[@]}")
[ ${#permflag[@]} -gt 0 ] && final+=("${permflag[@]}")
exec command claude "${final[@]}"
