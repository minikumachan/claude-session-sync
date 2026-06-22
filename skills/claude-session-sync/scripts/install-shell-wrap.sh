#!/usr/bin/env bash
#  claude-session-sync : シェル統合(`claude -h`=履歴UI / `claude -a`=自動起動設定)(macOS / Linux)
#  どのシェルからでも横取りできるよう 2 系統で導入する:
#    (A) ~/.bashrc / ~/.zshrc に claude() 関数(対話シェルで最速)。
#    (B) ~/.claude/css-bin に shim(claude)を置き PATH 先頭へ追加(関数が無い状況の保険)。
#  -h/--history=履歴UI、-a/--autostart=自動起動・リモート設定。-r(公式 --resume)等は実体の claude へ素通し。
#  css-bin はデバイス毎ローカル(同期される ~/.claude/skills 配下には置かない)。
#    install-shell-wrap.sh            # 導入
#    install-shell-wrap.sh --uninstall # 削除
set -euo pipefail
UNINSTALL=0; [[ "${1:-}" == "--uninstall" ]] && UNINSTALL=1
BIN="$HOME/.claude/css-bin"
BEGIN="# >>> claude-session-sync >>>"
END="# <<< claude-session-sync <<<"

# ===== (B) css-bin の shim =====
if [[ $UNINSTALL -eq 0 ]]; then
  mkdir -p "$BIN"
  cat > "$BIN/claude" <<'SHIM'
#!/bin/sh
# claude-session-sync shim (macOS / Linux)
DIR="$HOME/.claude/skills/claude-session-sync/scripts"
case "${1:-}" in
  -h|--history)   exec bash "$DIR/history-ui.sh" ;;
  -a|--autostart) exec bash "$DIR/autostart-ui.sh" ;;
esac
self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
real=""
oldifs="$IFS"; IFS=:
for d in $PATH; do
  [ "$d" = "$self" ] && continue
  if [ -f "$d/claude" ] && [ -x "$d/claude" ]; then real="$d/claude"; break; fi
done
IFS="$oldifs"
[ -n "$real" ] || { echo "[claude-session-sync] real claude not found on PATH" >&2; exit 1; }
exec "$real" "$@"
SHIM
  chmod +x "$BIN/claude"
  echo "✔ shim: $BIN/claude"
else
  rm -rf "$BIN" 2>/dev/null || true
  echo "✔ shim 削除: $BIN"
fi

# ===== (A) rc の関数 + PATH =====
BLOCK="$BEGIN
case \":\$PATH:\" in *\":\$HOME/.claude/css-bin:\"*) ;; *) PATH=\"\$HOME/.claude/css-bin:\$PATH\" ;; esac
claude() {
  if [ \"\${1:-}\" = \"-h\" ] || [ \"\${1:-}\" = \"--history\" ]; then
    bash \"\$HOME/.claude/skills/claude-session-sync/scripts/history-ui.sh\"
  elif [ \"\${1:-}\" = \"-a\" ] || [ \"\${1:-}\" = \"--autostart\" ]; then
    bash \"\$HOME/.claude/skills/claude-session-sync/scripts/autostart-ui.sh\"
  else
    command claude \"\$@\"
  fi
}
c()   { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" c \"\$@\"; }
cfp() { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" cfp \"\$@\"; }
cp()  { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" cp \"\$@\"; }   # 固定パス起動(coreutils cp を上書き。コピーは command cp / /bin/cp)
cc()  { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" cc \"\$@\"; }
ch()  { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" ch \"\$@\"; }
ca()  { bash \"\$HOME/.claude/skills/claude-session-sync/scripts/cgo.sh\" ca \"\$@\"; }
$END"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ "$rc" == "$HOME/.bashrc" || -e "$rc" ]] || continue
  touch "$rc"
  # 旧/新どちらの claude-session-sync ブロックも除去(冪等・-r版からの移行対応)
  tmp="$(mktemp)"
  awk -v e="$END" 'BEGIN{s=0} /^# >>> claude-session-sync/{s=1} s==0{print} $0==e{s=0}' "$rc" > "$tmp" && mv "$tmp" "$rc"
  if [[ $UNINSTALL -eq 0 ]]; then printf '\n%s\n' "$BLOCK" >> "$rc"; echo "✔ 導入: $rc"; else echo "✔ 削除: $rc"; fi
done
if [[ $UNINSTALL -eq 0 ]]; then
  echo "新しいシェルを開く(または source)と、どのシェルでも claude -h=履歴UI / claude -a=自動起動・リモート設定 / claude -r 等は公式のままになります。"
  echo "ショートカット: c=通常起動 / cfp・cp=固定パス起動 / cc=直前の会話を再開 / ch=履歴UI / ca=設定。固定パス・リモートは『claude -a』→ 起動ショートカット設定 で。"
  echo "※ cp は coreutils の cp を上書きします。ファイルコピーは command cp / /bin/cp をご利用ください。"
else
  echo "解除しました。新しいシェルを開くと完全に元へ戻ります。"
fi
