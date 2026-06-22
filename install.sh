#!/usr/bin/env bash
#  claude-session-sync : 対話インストーラ (macOS / Linux)
#  既定で順に質問: 共有する/しない → コンポーネント → 同期フォルダ → prepare → フック → リンク案内
#  非対話: --share を渡すか --non-interactive。--local/--skills/--mcp/--no-projects/--hooks。
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SKILL="$REPO/skills/claude-session-sync"
DEST="$HOME/.claude/skills/claude-session-sync"

SHARE=""; LOCAL=0; SKILLS=0; MCP=0; NOPROJ=0; HOOKS=0; LOCKSCOPE="project"; NONINT=0
P_SET=0; S_SET=0; M_SET=0; H_SET=0
while [[ $# -gt 0 ]]; do case "$1" in
  --share) SHARE="$2"; shift 2;;
  --local) LOCAL=1; shift;;
  --skills|--with-skills) SKILLS=1; S_SET=1; shift;;
  --mcp) MCP=1; M_SET=1; shift;;
  --no-projects) NOPROJ=1; P_SET=1; shift;;
  --hooks) HOOKS=1; H_SET=1; shift;;
  --no-hooks) HOOKS=0; H_SET=1; shift;;
  --lock-scope) LOCKSCOPE="$2"; shift 2;;
  --non-interactive) NONINT=1; shift;;
  *) shift;;
esac; done

INTERACTIVE=1
{ [[ $NONINT -eq 1 || -n "$SHARE" || $LOCAL -eq 1 ]] && INTERACTIVE=0; } || true

ask_yn(){ # $1=question $2=default(0/1)
  if [[ $INTERACTIVE -ne 1 ]]; then return $(( $2 ==1 ? 0 : 1 )); fi
  local d; [[ "$2" == "1" ]] && d="Y/n" || d="y/N"
  read -r -p "$1 [$d] " a
  [[ -z "$a" ]] && return $(( $2 ==1 ? 0 : 1 ))
  [[ "$a" =~ ^([yY]|yes)$ ]]
}

mkdir -p "$DEST"; cp -R "$REPO_SKILL"/. "$DEST"/
chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true
echo "✔ スキルを配置: $DEST"
SCRIPTS="$DEST/scripts"

# 0) 必要環境のチェック(claude 本体 / python3+curses など)。不足は案内し、対話時は導入を確認。
echo; echo "必要な環境を確認します..."
bash "$SCRIPTS/check-deps.sh" || true

# 共有する/しない
DO_SHARE=1
if [[ $LOCAL -eq 1 ]]; then DO_SHARE=0
elif [[ $INTERACTIVE -eq 1 ]]; then
  echo
  echo "会話履歴の扱いを選んでください:"
  echo "  [1] 共有する   … 同期フォルダ(Syncthing/iCloud等)へリンクして複数機で共有"
  echo "  [2] 共有しない … 既存の ~/.claude のまま(スキルだけ入れて後で設定)"
  read -r -p "選択 [1/2] " s; [[ "$s" == "2" ]] && DO_SHARE=0
fi
if [[ $DO_SHARE -eq 0 ]]; then
  echo; echo "共有はしません。スキルのみ導入しました。"
  echo "後で共有を始めるには:  bash \"$SCRIPTS/setup.sh\" --share '<同期先/_ClaudeCode>' --phase prepare"
  exit 0
fi

# コンポーネント
COMP_P=1; [[ $NOPROJ -eq 1 ]] && COMP_P=0
COMP_S=$SKILLS; COMP_M=$MCP
if [[ $INTERACTIVE -eq 1 ]]; then
  echo; echo "共有するコンポーネントを選択(ON/OFF):"
  ask_yn "  projects(会話履歴)を共有しますか?" 1 && COMP_P=1 || COMP_P=0
  ask_yn "  skills(スキル)を共有しますか?" 0 && COMP_S=1 || COMP_S=0
  ask_yn "  mcp(MCPサーバ定義)を共有しますか?" 0 && COMP_M=1 || COMP_M=0
fi

# 同期フォルダ
if [[ -z "$SHARE" ]]; then
  echo; echo "同期フォルダ候補を検出中..."
  mapfile -t ROWS < <(bash "$SCRIPTS/detect-sync.sh")
  i=0; PATHS=()
  for r in "${ROWS[@]}"; do i=$((i+1)); PATHS+=("${r#*$'\t'}"); printf '  [%d] %s\n' "$i" "$r"; done
  echo
  read -r -p "番号を選択、または共有ルートのパスを直接入力: " sel
  if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le ${#PATHS[@]} ]]; then root="${PATHS[$((sel-1))]}"; else root="$sel"; fi
  SHARE="$root/_ClaudeCode"
fi
echo "共有先(_ClaudeCode): $SHARE"

# prepare
SA=(--share "$SHARE" --lock-scope "$LOCKSCOPE" --phase prepare)
[[ $COMP_P -eq 0 ]] && SA+=(--no-projects)
[[ $COMP_S -eq 1 ]] && SA+=(--skills)
[[ $COMP_M -eq 1 ]] && SA+=(--mcp)
bash "$SCRIPTS/setup.sh" "${SA[@]}"

# フック
WANT_HOOKS=$HOOKS
if [[ $INTERACTIVE -eq 1 ]]; then ask_yn "自動ロックのフックを導入しますか?" 1 && WANT_HOOKS=1 || WANT_HOOKS=0; fi
[[ $WANT_HOOKS -eq 1 ]] && bash "$SCRIPTS/install-hooks.sh"

# シェル統合(claude -h=履歴UI / claude -a=設定 を bash/zsh で使えるように)
WANT_WRAP=1
if [[ $INTERACTIVE -eq 1 ]]; then ask_yn "シェル統合を導入しますか?(claude -h=履歴UI / claude -a=設定)" 1 && WANT_WRAP=1 || WANT_WRAP=0; fi
[[ $WANT_WRAP -eq 1 ]] && bash "$SCRIPTS/install-shell-wrap.sh"

echo
echo "=== 次の手順(リンク作成・破壊的)==="
echo "Claude Code を全終了してから実行:"
echo "  bash \"$SCRIPTS/setup.sh\" --phase link         # まずドライランで内容確認"
echo "  bash \"$SCRIPTS/setup.sh\" --phase link --yes    # 同意後に実行"
[[ $COMP_M -eq 1 ]] && echo "MCP を同期するには:  bash \"$SCRIPTS/mcp-sync.sh\" --export  /  --import --yes"
echo "完了後の起動: 通常の 'claude'(フック導入時は自動ロック) もしくは ロック付き 'cc.sh'。"
