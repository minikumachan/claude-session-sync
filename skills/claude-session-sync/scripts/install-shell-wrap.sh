#!/usr/bin/env bash
#  claude-session-sync : シェル統合(`claude -r` で全履歴ピッカー)(macOS / Linux)
#  ~/.bashrc / ~/.zshrc に claude() 関数を追加し、-r/--resume を resume-all.sh に振り向ける。
#    install-shell-wrap.sh            # 導入
#    install-shell-wrap.sh --uninstall # 削除
set -euo pipefail
UNINSTALL=0; [[ "${1:-}" == "--uninstall" ]] && UNINSTALL=1
BEGIN="# >>> claude-session-sync (claude -r = all history) >>>"
END="# <<< claude-session-sync <<<"
BLOCK="$BEGIN
claude() {
  if [ \"\${1:-}\" = \"-r\" ] || [ \"\${1:-}\" = \"--resume\" ]; then
    shift; bash \"\$HOME/.claude/skills/claude-session-sync/scripts/resume-all.sh\" \"\$@\"
  else
    command claude \"\$@\"
  fi
}
$END"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ "$rc" == "$HOME/.bashrc" || -e "$rc" ]] || continue
  touch "$rc"
  if grep -qF "$BEGIN" "$rc"; then
    tmp="$(mktemp)"
    awk -v b="$BEGIN" -v e="$END" 'BEGIN{s=0} $0==b{s=1} s==0{print} $0==e{s=0}' "$rc" > "$tmp" && mv "$tmp" "$rc"
  fi
  if [[ $UNINSTALL -eq 0 ]]; then printf '\n%s\n' "$BLOCK" >> "$rc"; echo "✔ 導入: $rc"; else echo "✔ 削除: $rc"; fi
done
echo "新しいシェルを開く(または source ~/.bashrc)と claude -r が全履歴ピッカーになります。"
