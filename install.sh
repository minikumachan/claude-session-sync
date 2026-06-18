#!/usr/bin/env bash
#  claude-session-sync : ワンショットインストーラ (macOS / Linux)
#  スキル配置 → 同期フォルダ選択 → 非破壊セットアップ(prepare) → (任意)自動ロックフック
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SKILL="$REPO/skills/claude-session-sync"
DEST="$HOME/.claude/skills/claude-session-sync"

SHARE=""; WITH_SKILLS=0; HOOKS=0; LOCKSCOPE="project"
while [[ $# -gt 0 ]]; do case "$1" in
  --share) SHARE="$2"; shift 2;;
  --with-skills) WITH_SKILLS=1; shift;;
  --hooks) HOOKS=1; shift;;
  --lock-scope) LOCKSCOPE="$2"; shift 2;;
  *) shift;;
esac; done

mkdir -p "$DEST"
cp -R "$REPO_SKILL"/. "$DEST"/
chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true
echo "✔ スキルを配置: $DEST"
SCRIPTS="$DEST/scripts"

if [[ -z "$SHARE" ]]; then
  echo
  echo "同期フォルダ候補を検出中..."
  mapfile -t ROWS < <(bash "$SCRIPTS/detect-sync.sh")
  i=0; PATHS=()
  for r in "${ROWS[@]}"; do
    i=$((i+1)); label="${r%%$'\t'*}"; path="${r#*$'\t'}"; PATHS+=("$path")
    printf '  [%d] %s  ->  %s\n' "$i" "$label" "$path"
  done
  echo
  read -r -p "番号を選択、または共有ルートのパスを直接入力: " sel
  if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le ${#PATHS[@]} ]]; then root="${PATHS[$((sel-1))]}"; else root="$sel"; fi
  SHARE="$root/_ClaudeCode"
fi
echo "共有先(_ClaudeCode): $SHARE"

SA=(--share "$SHARE" --lock-scope "$LOCKSCOPE" --phase prepare)
[[ $WITH_SKILLS -eq 1 ]] && SA+=(--with-skills)
bash "$SCRIPTS/setup.sh" "${SA[@]}"

[[ $HOOKS -eq 1 ]] && bash "$SCRIPTS/install-hooks.sh"

echo
echo "=== 次の手順(リンク作成)==="
echo "Claude Code を全終了してから実行:"
echo "  bash \"$SCRIPTS/setup.sh\" --phase link"
echo "完了後の起動: 通常の 'claude'(フック導入時は自動ロック) もしくは ロック付き 'cc.sh'。"
