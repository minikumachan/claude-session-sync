#!/usr/bin/env bash
#  claude-session-sync : 自動ロック用フックを ~/.claude/settings.json に導入/削除 (macOS / Linux)
set -euo pipefail
UNINSTALL=0; [[ "${1:-}" == "--uninstall" ]] && UNINSTALL=1
SETTINGS="$HOME/.claude/settings.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACQ="bash \"$DIR/hook-lock.sh\" acquire"
REL="bash \"$DIR/hook-lock.sh\" release"
BEAT="bash \"$DIR/hook-lock.sh\" beat"
TTL="bash \"$DIR/hook-title.sh\""
DSW="bash \"$DIR/hook-devswitch.sh\""
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "python3 が必要です(settings.json の安全なマージに使用)。手動で hooks を設定してください。" >&2; exit 1; }

ACQ="$ACQ" REL="$REL" BEAT="$BEAT" TTL="$TTL" DSW="$DSW" SETTINGS="$SETTINGS" UNINST="$UNINSTALL" "$PY" - <<'PYEOF'
import json, os
p=os.environ['SETTINGS']; acq=os.environ['ACQ']; rel=os.environ['REL']; beat=os.environ['BEAT']; ttl=os.environ['TTL']; dsw=os.environ['DSW']; uninstall=os.environ['UNINST']=='1'
markers=('hook-lock.sh','hook-title.sh','hook-devswitch.sh')
try:
    with open(p) as f: data=json.load(f)
except FileNotFoundError:
    data={}
except json.JSONDecodeError:
    raise SystemExit('settings.json が壊れています: '+p)
if not isinstance(data, dict): raise SystemExit('settings.json の形式が不正です')
hooks=data.setdefault('hooks', {})
def clean(lst):
    return [g for g in (lst or []) if not any(any(m in h.get('command','') for m in markers) for h in g.get('hooks',[]))]
for evt in ('SessionStart','SessionEnd','Stop','UserPromptSubmit'):
    hooks[evt]=clean(hooks.get(evt))
if not uninstall:
    hooks['SessionStart'].append({'hooks':[{'type':'command','command':acq}]})
    hooks['SessionStart'].append({'hooks':[{'type':'command','command':dsw}]})
    hooks['SessionEnd'].append({'hooks':[{'type':'command','command':rel}]})
    hooks['Stop'].append({'hooks':[{'type':'command','command':ttl}]})
    hooks['UserPromptSubmit'].append({'hooks':[{'type':'command','command':beat}]})   # 実行中ハートビート(アクセス中表示を確実に)
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p,'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
print(('✔ 自動ロック/自動タイトルのフックを削除' if uninstall else '✔ 自動ロック/自動タイトルのフックを設定')+': '+p)
PYEOF
