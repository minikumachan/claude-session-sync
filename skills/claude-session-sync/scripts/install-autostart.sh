#!/usr/bin/env bash
#  claude-session-sync : 自動起動 / リモート起動の設定 (macOS / Linux)
#    起動項目は ~/.claude/session-sync.boot.json(配列)、共通設定は session-sync.local.conf。
#    通常は対話メニュー `claude -a`(autostart-ui.sh)から呼ばれる。フラグ直接指定:
#      install-autostart.sh --launch new [--model sonnet] [--effort medium] [--remote|--no-remote|--remote-mode ask]
#      install-autostart.sh --launch last | --session <sid>   # 会話のモデル/深度を使用
#      install-autostart.sh --watch | --apply | --status | --uninstall
set -euo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"; BJ="$CLAUDE/session-sync.boot.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup.sh を実行してください。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
setkv(){ local k="$1" v="$2" tmp; tmp="$(mktemp)"
  if grep -qE "^$k=" "$CFG"; then sed "s|^$k=.*|$k=$v|" "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  else cat "$CFG" > "$tmp"; printf '%s=%s\n' "$k" "$v" >> "$tmp"; mv "$tmp" "$CFG"; fi; }
PY="$(command -v python3 || command -v python || true)"

LAUNCH=""; SESSION=""; MODEL=""; EFFORT=""; EFFORT_SET=0; REMOTE=""; CHECK=""; WATCH=""; WATCHDIR=""
APPLY=0; UNINSTALL=0; STATUS=0; HAVE_LAUNCH=0
while [[ $# -gt 0 ]]; do case "$1" in
  --launch) LAUNCH="$2"; HAVE_LAUNCH=1; shift 2;;
  --session) SESSION="$2"; shift 2;;
  --model) MODEL="$2"; shift 2;;
  --effort) EFFORT="$2"; EFFORT_SET=1; shift 2;;
  --remote) REMOTE="true"; shift;;
  --no-remote) REMOTE="false"; shift;;
  --remote-mode) REMOTE="$2"; shift 2;;
  --check-multi) CHECK="true"; shift;;
  --no-check-multi) CHECK="false"; shift;;
  --watch) WATCH="true"; shift;;
  --no-watch) WATCH="false"; shift;;
  --watch-dir) WATCHDIR="$2"; shift 2;;
  --apply) APPLY=1; shift;;
  --uninstall) UNINSTALL=1; shift;;
  --status) STATUS=1; shift;;
  *) shift;;
esac; done

OS="$(uname)"
LA_DIR="$HOME/Library/LaunchAgents"; AS_DIR="$HOME/.config/autostart"
BOOT_PLIST="$LA_DIR/com.claude-session-sync.boot.plist"; WATCH_PLIST="$LA_DIR/com.claude-session-sync.watch.plist"
BOOT_DESKTOP="$AS_DIR/claude-session-sync-boot.desktop"; WATCH_DESKTOP="$AS_DIR/claude-session-sync-watch.desktop"

entry_count(){ [[ -f "$BJ" && -n "$PY" ]] || { echo 0; return; }; "$PY" - "$BJ" <<'PYEOF'
import json,sys
try: a=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: a=[]
if isinstance(a,dict): a=[a]
print(len(a or []))
PYEOF
}

unregister(){ if [[ "$OS" == "Darwin" ]]; then local pl; [[ "$1" == boot ]] && pl="$BOOT_PLIST" || pl="$WATCH_PLIST"; [[ -f "$pl" ]] && { launchctl unload "$pl" 2>/dev/null || true; rm -f "$pl"; }
  else [[ "$1" == boot ]] && rm -f "$BOOT_DESKTOP" || rm -f "$WATCH_DESKTOP"; fi; }
register_boot(){ if [[ "$OS" == "Darwin" ]]; then mkdir -p "$LA_DIR"; cat > "$BOOT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claude-session-sync.boot</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/osascript</string><string>-e</string><string>tell application "Terminal" to do script "bash '$DIR/boot-launch.sh'"</string></array>
</dict></plist>
PLIST
    launchctl unload "$BOOT_PLIST" 2>/dev/null || true; launchctl load "$BOOT_PLIST" 2>/dev/null || true
  else mkdir -p "$AS_DIR"; local term="x-terminal-emulator"; command -v "$term" >/dev/null 2>&1 || term="gnome-terminal"; cat > "$BOOT_DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Claude Session Sync (boot)
Exec=$term -e bash "$DIR/boot-launch.sh"
X-GNOME-Autostart-enabled=true
DESK
  fi; }
register_watch(){ if [[ "$OS" == "Darwin" ]]; then mkdir -p "$LA_DIR"; cat > "$WATCH_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claude-session-sync.watch</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/remote-watch.sh</string></array>
</dict></plist>
PLIST
    launchctl unload "$WATCH_PLIST" 2>/dev/null || true; launchctl load "$WATCH_PLIST" 2>/dev/null || true
  else mkdir -p "$AS_DIR"; cat > "$WATCH_DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Claude Session Sync (remote watcher)
Exec=bash "$DIR/remote-watch.sh"
X-GNOME-Autostart-enabled=true
DESK
  fi; }
do_register(){
  if [[ "$(entry_count)" -gt 0 ]]; then register_boot; else unregister boot; fi
  if [[ "$(get remoteWatch)" == "true" ]]; then register_watch; local wd; wd="$(get remoteWatchDir)"; [[ -z "$wd" ]] && wd="$(get share)/remote"; mkdir -p "$wd/inbox"; else unregister watch; fi
}

if [[ $STATUS -eq 1 ]]; then
  echo "=== 自動起動 / リモート起動 状態 ($OS) ==="
  if [[ -f "$BJ" && -n "$PY" ]]; then echo "自動起動する会話:"; "$PY" - "$BJ" <<'PYEOF'
import json,sys
try: a=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: a=[]
if isinstance(a,dict): a=[a]
for i,e in enumerate(a or [],1):
    t=e.get('type','new')
    if t=='new': d="新規(壁打ち) model=%s effort=%s"%(e.get('model') or '(既定)', e.get('effort') or '(既定)')
    elif t=='last': d="最近の会話を再開 (会話のモデル/深度)"
    else: d="特定の会話 sid=%s (会話のモデル/深度)"%e.get('sid','')
    print("  %d) %s  リモート=%s"%(i,d,e.get('remote',False)))
PYEOF
  else echo "自動起動する会話: なし"; fi
  echo "共通: 多重起動チェック=$(get bootCheckMulti)  スマホからの起動=$(get remoteWatch)"
  exit 0
fi

if [[ $UNINSTALL -eq 1 ]]; then unregister boot; unregister watch; rm -f "$BJ"; setkv bootLaunch off; setkv remoteWatch false
  echo "✔ 自動起動 / リモート起動ウォッチャを解除しました(項目削除・設定 off)。"; exit 0; fi

if [[ $APPLY -eq 1 ]]; then do_register; echo "✔ shortcut/agent を現在の設定に合わせて再登録しました。"; exit 0; fi

# 単一項目をフラグから boot.json に書く
if [[ $HAVE_LAUNCH -eq 1 || -n "$SESSION" ]]; then
  if [[ "$LAUNCH" == off ]]; then rm -f "$BJ"
  elif [[ -n "$PY" ]]; then
    rem="ask"; case "$REMOTE" in true) rem=true;; false) rem=false;; ask) rem=ask;; esac
    BJ="$BJ" T="$([[ -n "$SESSION" ]] && echo resume || echo "${LAUNCH:-new}")" SID="$SESSION" MODEL="$MODEL" EFFORT="$EFFORT" ESET="$EFFORT_SET" REM="$rem" "$PY" - <<'PYEOF'
import json,os
t=os.environ['T']; e={"type":t}
if t=="resume": e["sid"]=os.environ.get('SID','')
if t=="new":
    e["model"]=os.environ.get('MODEL') or "sonnet"
    e["effort"]=os.environ.get('EFFORT') if os.environ.get('ESET')=='1' else "medium"
r=os.environ['REM']; e["remote"]= True if r=="true" else (False if r=="false" else "ask")
json.dump([e], open(os.environ['BJ'],'w',encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
  fi
fi

[[ -n "$CHECK" ]] && setkv bootCheckMulti "$CHECK" || { [[ -z "$(get bootCheckMulti)" ]] && setkv bootCheckMulti true; }
[[ -n "$WATCH" ]] && setkv remoteWatch "$WATCH" || { [[ -z "$(get remoteWatch)" ]] && setkv remoteWatch false; }
[[ -n "$WATCHDIR" ]] && setkv remoteWatchDir "$WATCHDIR"

do_register
echo "✔ 保存しました。自動起動項目=$(entry_count)件  多重起動チェック=$(get bootCheckMulti)  スマホからの起動=$(get remoteWatch)"
echo "完了。変更は次回ログインから有効です。"
