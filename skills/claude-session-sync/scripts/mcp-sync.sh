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
get(){ grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r'; }
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
# ローカル MCP 定義を集約: top-level(user)+ 各 projects[<cwd>].mcpServers(local)。名前で重複排除(top-level 優先)。
# `claude mcp add` は既定で local(プロジェクト)スコープに保存されるため top-level だけ見ると空に見える。
def collect_local(data):
    alls={}
    for pv in (data.get('projects') or {}).values():
        for s,v in (pv.get('mcpServers') or {}).items(): alls.setdefault(s,v)
    for s,v in (data.get('mcpServers') or {}).items(): alls[s]=v
    return alls
def claudeai_note(data):
    ca=data.get('claudeAiMcpEverConnected') or []
    if ca:
        names=', '.join(str(x).replace('claude.ai ','') for x in ca)
        print('ℹ claude.ai 接続(%s)はアカウント連携です。別デバイスで claude.ai にログインすれば自動で使えます(本ツールのファイル共有の対象外。`claude mcp list` で現在の接続を確認できます)。'%names)
ts=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')

if mode=='status':
    data=load(local); ls=collect_local(data)
    sh=(load(shared).get('mcpServers') if os.path.exists(shared) else {}) or {}
    print('=== MCP 共有状態 ===')
    print('ローカル MCP 定義(user＋各プロジェクト) [%d]:'%len(ls), ', '.join(ls))
    print('共有ファイル:', shared, '(存在=%s)'%os.path.exists(shared))
    print('共有サーバ [%d]:'%len(sh), ', '.join(sh))
    claudeai_note(data)
    if not ls: print('(共有できるローカル定義はありません。`claude mcp add` で追加した stdio/http 定義のみが対象です。)')
elif mode=='export':
    data=load(local); servers=collect_local(data)
    if not servers:
        print('共有できるローカル MCP サーバ定義がありません(~/.claude.json の user・各プロジェクト いずれも空)。')
        claudeai_note(data)
        print('→ 共有対象は `claude mcp add` で追加した stdio/http 定義のみ。claude.ai 接続は対象外(ログインで同期)。')
        sys.exit(0)
    if strip:
        for s in servers.values(): s['env']={}
    if has_secrets(servers) and not strip and not yes:
        print('⚠ env に秘密が含まれる可能性。共有フォルダ(%s)に書き込まれます。'%shared)
        print('  続行=--yes / env 除外=--strip-env を付けて再実行。'); sys.exit(0)
    if os.path.exists(shared): shutil.copy(shared, shared+'.bak_'+ts)
    json.dump({'mcpServers':servers,'_generatedBy':'claude-session-sync','_exportedFrom':host},
              open(shared,'w'), indent=2, ensure_ascii=False)
    try: os.chmod(shared, 0o600)   # 秘密が含まれ得るので所有者のみ読み書き
    except Exception: pass
    print('✔ エクスポート: %d サーバ -> %s'%(len(servers),shared))
    if has_secrets(servers): print('  (env を含めて書き出しました)')
elif mode=='import':
    if not os.path.exists(shared):
        print('共有 MCP 定義ファイルがまだありません:', shared)
        print('→ 先に【共有元の機】で「書き出す(Export)」を実行してください。共有できるのは `claude mcp add` のローカル定義のみ。')
        claudeai_note(load(local)); sys.exit(0)
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
