#!/usr/bin/env bash
#  claude-session-sync : シェル統合(`claude -h` で履歴ブラウザUI)(macOS / Linux)
#  ~/.bashrc / ~/.zshrc に claude() 関数を追加し、-h/--history を history-ui.sh に振り向ける。
#  -r(公式 --resume)を含む他の引数は実体の claude へ素通し。
#    install-shell-wrap.sh            # 導入
#    install-shell-wrap.sh --uninstall # 削除
set -euo pipefail
UNINSTALL=0; [[ "${1:-}" == "--uninstall" ]] && UNINSTALL=1
BEGIN="# >>> claude-session-sync >>>"
END="# <<< claude-session-sync <<<"
BLOCK="$BEGIN
claude() {
  if [ \"\${1:-}\" = \"-h\" ] || [ \"\${1:-}\" = \"--history\" ]; then
    bash \"\$HOME/.claude/skills/claude-session-sync/scripts/history-ui.sh\"
  elif [ \"\${1:-}\" = \"-a\" ] || [ \"\${1:-}\" = \"--autostart\" ]; then
    bash \"\$HOME/.claude/skills/claude-session-sync/scripts/autostart-ui.sh\"
  else
    command claude \"\$@\"
  fi
}
$END"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ "$rc" == "$HOME/.bashrc" || -e "$rc" ]] || continue
  touch "$rc"
  # 旧/新どちらの claude-session-sync ブロックも除去(-r版からの移行対応)
  tmp="$(mktemp)"
  awk -v e="$END" 'BEGIN{s=0} /^# >>> claude-session-sync/{s=1} s==0{print} $0==e{s=0}' "$rc" > "$tmp" && mv "$tmp" "$rc"
  if [[ $UNINSTALL -eq 0 ]]; then printf '\n%s\n' "$BLOCK" >> "$rc"; echo "✔ 導入: $rc"; else echo "✔ 削除: $rc"; fi
done
echo "新しいシェルを開く(または source)と、claude -h=履歴UI / claude -a=自動起動・リモート設定 / claude -r は公式のままになります。"
