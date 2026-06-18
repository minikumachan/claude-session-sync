#!/usr/bin/env bash
#  claude-session-sync : 同期フォルダ候補を自動検出 (macOS / Linux)
#  出力: 1行 = "LABEL<TAB>PATH"
emit(){ [[ -d "$2" ]] && printf '%s\t%s\n' "$1" "$2"; }
shopt -s nullglob   # マッチしない glob を空に(OneDrive* 等の誤展開防止)

case "$(uname -s)" in
  Darwin) emit "iCloud Drive" "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ;;
esac
emit "Dropbox" "$HOME/Dropbox"
emit "Google Drive" "$HOME/Google Drive"
emit "Google Drive (CloudStorage)" "$HOME/Library/CloudStorage/GoogleDrive"
for d in "$HOME"/OneDrive*; do emit "OneDrive" "$d"; done

for cfg in "$HOME/.config/syncthing/config.xml" \
           "$HOME/Library/Application Support/Syncthing/config.xml" \
           "$HOME/.local/state/syncthing/config.xml"; do
  if [[ -f "$cfg" ]]; then
    grep -oE 'path="[^"]+"' "$cfg" | sed 's/path="//;s/"$//' | while read -r p; do emit "Syncthing" "$p"; done
  fi
done
