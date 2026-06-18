#!/usr/bin/env bash
#  claude-session-sync : MCP サーバ定義の共有 (macOS / Linux)
#  ~/.claude.json はリンクせず、mcpServers だけを共有ファイルと export/import する。
#    --status (既定) / --export / --import(破壊的: --yes 必須) / --strip-env
set -euo pipefail
MODE=status; STRIP=0; YES=0
while [[ $# -gt 0 ]]; do case "$1" in
  --export) MODE=export; shift;;
  --import) MODE=import; shift;;
  --status) MODE=status; shift;;
  --strip-env) STRIP=1; shift;;
  --yes) YES=1; shift;;
  *) shift;;
esac; done
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "未設定です。setup.sh を先に。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-; }
SHARE="$(get share)"; [[ -n "$SHARE" ]] || { echo "config に share なし" >&2; exit 1; }
mkdir -p "$SHARE/mcp"
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "python3 が必要です(安全な JSON 編集に使用)。" >&2; exit 1; }

SHARED="$SHARE/mcp/servers.json" LOCAL="$HOME/.claude.json" MODE="$MODE" STRIP="$STRIP" YES="$YES" HOST="$(hostname)" "$PY" - <<'PYEOF'
import json, os, shutil, datetime, sys
shared=os.environ['SHARED']; local=os.environ['LOCAL']; mode=os.environ['MODE']
strip=os.environ['STRIP']=='1'; yes=os.environ['YES']=='1'; host=os.environ['HOST']
def load(p):
    try:
        with open(p) as f: return json.load(f)
    except FileNotFoundError: return {}
    except json.JSONDecodeError: sys.exit('JSON が壊れています: '+p)
def has_secrets(servers): return any((s.get('env') or {}) for s in servers.values())
ts=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')

if mode=='status':
    ls=load(local).get('mcpServers') or {}
    sh=(load(shared).get('mcpServers') if os.path.exists(shared) else {}) or {}
    print('=== MCP 共有状態 ===')
    print('ローカル サーバ:', ', '.join(ls))
    print('共有ファイル:', shared, '(存在=%s)'%os.path.exists(shared))
    print('共有サーバ:', ', '.join(sh))
elif mode=='export':
    servers=load(local).get('mcpServers') or {}
    if not servers: print('ローカルに MCP 定義なし。エクスポート不要。'); sys.exit(0)
    if strip:
        for s in servers.values(): s['env']={}
    if has_secrets(servers) and not strip and not yes:
        print('⚠ env に秘密が含まれる可能性。共有フォルダ(%s)に書き込まれます。'%shared)
        print('  続行=--yes / env 除外=--strip-env を付けて再実行。'); sys.exit(0)
    if os.path.exists(shared): shutil.copy(shared, shared+'.bak_'+ts)
    json.dump({'mcpServers':servers,'_generatedBy':'claude-session-sync','_exportedFrom':host},
              open(shared,'w'), indent=2, ensure_ascii=False)
    print('✔ エクスポート: %d サーバ -> %s'%(len(servers),shared))
    if has_secrets(servers): print('  (env を含めて書き出しました)')
elif mode=='import':
    if not os.path.exists(shared): sys.exit('共有 MCP 定義なし: '+shared)
    sh=load(shared).get('mcpServers') or {}
    if not sh: print('共有に MCP サーバなし。'); sys.exit(0)
    data=load(local); data.setdefault('mcpServers',{})
    added=[k for k in sh if k not in data['mcpServers']]; updated=[k for k in sh if k in data['mcpServers']]
    print('取り込み予定: 追加=[%s] 更新=[%s]'%(', '.join(added),', '.join(updated)))
    if not yes:
        print('⚠⚠ ~/.claude.json を書き換える破壊的操作 ⚠⚠  実行は --yes(自動バックアップ＋検証)。'); sys.exit(0)
    shutil.copy(local, local+'.bak_'+ts)
    data['mcpServers'].update(sh)
    tmp=local+'.tmp_css'
    json.dump(data, open(tmp,'w'), indent=2, ensure_ascii=False)
    json.load(open(tmp))  # validate
    os.replace(tmp, local)
    print('✔ 取り込み完了(追加 %d / 更新 %d)。Claude 再起動で反映。'%(len(added),len(updated)))
    print('  バックアップ: %s.bak_%s'%(local,ts))
PYEOF
