#!/usr/bin/env bash
#  claude-session-sync : 自動起動 / リモート起動の設定 (macOS / Linux)
#    - ログイン時に claude を自動起動(新規 / 最近 / 特定会話, リモート可)
#    - スマホ等からのトリガで `claude --remote-control` を起動する常駐ウォッチャ
#    macOS: ~/Library/LaunchAgents の LaunchAgent / Linux: ~/.config/autostart の .desktop
#
#    使い方:
#      install-autostart.sh --launch new            # ログイン時に新規会話で起動
#      install-autostart.sh --launch last --remote  # 最近の会話を再開 + リモートON
#      install-autostart.sh --session <sid>         # 特定の会話を毎回再開
#      install-autostart.sh --remote-mode ask       # 起動時にリモートON/OFFを尋ねる
#      install-autostart.sh --watch                 # スマホからのトリガ起動を有効化
#      install-autostart.sh --status
#      install-autostart.sh --uninstall
set -euo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup.sh を実行してください。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
setkv(){ local k="$1" v="$2" tmp; tmp="$(mktemp)"
  if grep -qE "^$k=" "$CFG"; then sed "s|^$k=.*|$k=$v|" "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  else cat "$CFG" > "$tmp"; printf '%s=%s\n' "$k" "$v" >> "$tmp"; mv "$tmp" "$CFG"; fi; }

LAUNCH=""; SESSION=""; REMOTE=""; CHECK=""; WATCH=""; WATCHDIR=""; UNINSTALL=0; STATUS=0
while [[ $# -gt 0 ]]; do case "$1" in
  --launch) LAUNCH="$2"; shift 2;;
  --session) SESSION="$2"; shift 2;;
  --remote) REMOTE="true"; shift;;
  --no-remote) REMOTE="false"; shift;;
  --remote-mode) REMOTE="$2"; shift 2;;
  --check-multi) CHECK="true"; shift;;
  --no-check-multi) CHECK="false"; shift;;
  --watch) WATCH="true"; shift;;
  --no-watch) WATCH="false"; shift;;
  --watch-dir) WATCHDIR="$2"; shift 2;;
  --uninstall) UNINSTALL=1; shift;;
  --status) STATUS=1; shift;;
  *) shift;;
esac; done

OS="$(uname)"
LA_DIR="$HOME/Library/LaunchAgents"
AS_DIR="$HOME/.config/autostart"
BOOT_PLIST="$LA_DIR/com.claude-session-sync.boot.plist"
WATCH_PLIST="$LA_DIR/com.claude-session-sync.watch.plist"
BOOT_DESKTOP="$AS_DIR/claude-session-sync-boot.desktop"
WATCH_DESKTOP="$AS_DIR/claude-session-sync-watch.desktop"

unregister(){  # $1=boot|watch
  if [[ "$OS" == "Darwin" ]]; then
    local pl; [[ "$1" == boot ]] && pl="$BOOT_PLIST" || pl="$WATCH_PLIST"
    [[ -f "$pl" ]] && { launchctl unload "$pl" 2>/dev/null || true; rm -f "$pl"; }
  else
    [[ "$1" == boot ]] && rm -f "$BOOT_DESKTOP" || rm -f "$WATCH_DESKTOP"
  fi
}
register_boot(){
  if [[ "$OS" == "Darwin" ]]; then
    mkdir -p "$LA_DIR"
    cat > "$BOOT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claude-session-sync.boot</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/osascript</string><string>-e</string>
    <string>tell application "Terminal" to do script "bash '$DIR/boot-launch.sh'"</string>
  </array>
</dict></plist>
PLIST
    launchctl unload "$BOOT_PLIST" 2>/dev/null || true; launchctl load "$BOOT_PLIST" 2>/dev/null || true
  else
    mkdir -p "$AS_DIR"
    local term="x-terminal-emulator"; command -v "$term" >/dev/null 2>&1 || term="gnome-terminal"
    cat > "$BOOT_DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Claude Session Sync (boot)
Exec=$term -e bash "$DIR/boot-launch.sh"
X-GNOME-Autostart-enabled=true
DESK
  fi
}
register_watch(){
  if [[ "$OS" == "Darwin" ]]; then
    mkdir -p "$LA_DIR"
    cat > "$WATCH_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claude-session-sync.watch</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/remote-watch.sh</string></array>
</dict></plist>
PLIST
    launchctl unload "$WATCH_PLIST" 2>/dev/null || true; launchctl load "$WATCH_PLIST" 2>/dev/null || true
  else
    mkdir -p "$AS_DIR"
    cat > "$WATCH_DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Claude Session Sync (remote watcher)
Exec=bash "$DIR/remote-watch.sh"
X-GNOME-Autostart-enabled=true
DESK
  fi
}

if [[ $STATUS -eq 1 ]]; then
  wd="$(get remoteWatchDir)"; [[ -z "$wd" ]] && wd="$(get share)/remote"
  echo "=== 自動起動 / リモート起動 状態 ($OS) ==="
  echo "bootLaunch=$(get bootLaunch)  bootRemote=$(get bootRemote)  bootCheckMulti=$(get bootCheckMulti)"
  echo "remoteWatch=$(get remoteWatch)  watchDir=$wd"
  if [[ "$OS" == "Darwin" ]]; then
    echo "boot LaunchAgent : $([[ -f "$BOOT_PLIST" ]] && echo 有 || echo 無)"
    echo "watch LaunchAgent: $([[ -f "$WATCH_PLIST" ]] && echo 有 || echo 無)"
  else
    echo "boot autostart : $([[ -f "$BOOT_DESKTOP" ]] && echo 有 || echo 無)"
    echo "watch autostart: $([[ -f "$WATCH_DESKTOP" ]] && echo 有 || echo 無)"
  fi
  exit 0
fi

if [[ $UNINSTALL -eq 1 ]]; then
  unregister boot; unregister watch
  setkv bootLaunch off; setkv remoteWatch false
  echo "✔ 自動起動 / リモート起動ウォッチャを解除しました(設定 off)。"; exit 0
fi

# --- 設定反映 ---
if [[ -n "$SESSION" ]]; then setkv bootLaunch "$SESSION"
elif [[ -n "$LAUNCH" ]]; then setkv bootLaunch "$LAUNCH"
elif [[ -z "$(get bootLaunch)" ]]; then setkv bootLaunch off; fi
[[ -n "$REMOTE" ]] && setkv bootRemote "$REMOTE" || { [[ -z "$(get bootRemote)" ]] && setkv bootRemote false; }
[[ -n "$CHECK" ]]  && setkv bootCheckMulti "$CHECK" || { [[ -z "$(get bootCheckMulti)" ]] && setkv bootCheckMulti true; }
[[ -n "$WATCH" ]]  && setkv remoteWatch "$WATCH" || { [[ -z "$(get remoteWatch)" ]] && setkv remoteWatch false; }
[[ -n "$WATCHDIR" ]] && setkv remoteWatchDir "$WATCHDIR"

BL="$(get bootLaunch)"
if [[ -n "$BL" && "$BL" != "off" ]]; then
  register_boot
  echo "✔ ログイン自動起動を登録: bootLaunch=$BL remote=$(get bootRemote) checkMulti=$(get bootCheckMulti)"
else
  unregister boot; echo "• 自動起動は off"
fi
if [[ "$(get remoteWatch)" == "true" ]]; then
  register_watch
  wd="$(get remoteWatchDir)"; [[ -z "$wd" ]] && wd="$(get share)/remote"
  mkdir -p "$wd/inbox"
  echo "✔ リモート起動ウォッチャを登録: 監視=$wd/inbox"
  echo "  → スマホから同期フォルダの inbox に1ファイル置くと claude --remote-control が起動します。"
else
  unregister watch
fi
echo "完了。変更は次回ログインから有効です(今すぐ試すには boot-launch.sh を直接実行)。"
