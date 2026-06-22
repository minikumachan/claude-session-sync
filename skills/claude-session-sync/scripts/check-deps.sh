#!/usr/bin/env bash
#  claude-session-sync : 必要環境のチェックと導入案内 (macOS / Linux)
#  claude -h(履歴UI)= python3(+curses) と claude 本体 が必須。git は git 同期方式利用時のみ。
#  不足があれば導入方法を案内し、可能ならインストールを確認の上で実行(--yes で確認省略)。
#    check-deps.sh          # チェックして結果表示
#    check-deps.sh --yes    # 不足の自動導入を確認なしで実行(パッケージ管理がある場合)
#    check-deps.sh --quiet  # 問題が無ければ無出力(初回起動チェック用。要対応時のみ表示)
set -uo pipefail
YES=0; QUIET=0
for a in "$@"; do case "$a" in --yes) YES=1;; --quiet) QUIET=1;; esac; done
miss=0; out=""
add(){ out="$out  $1"$'\n'; }

# claude 本体
if command -v claude >/dev/null 2>&1; then add "[OK] claude 本体: $(command -v claude)"
else add "[要対応] claude 本体が見つかりません"; add "      → Claude Code を導入: npm i -g @anthropic-ai/claude-code  (https://claude.com/claude-code)"; miss=1; fi

# bash
add "[OK] bash: ${BASH_VERSION:-?}"

# python3 (+curses) ← 履歴UI(claude -h)の必須
PY="$(command -v python3 || command -v python || true)"
PYOK=0
if [ -n "$PY" ] && "$PY" -c 'import curses' >/dev/null 2>&1; then PYOK=1; fi
if [ "$PYOK" -eq 1 ]; then
  add "[OK] python3 + curses: $("$PY" --version 2>&1)"
else
  if [ -n "$PY" ]; then add "[要対応] python はあるが curses が使えません: $PY"
  else add "[要対応] python3 が見つかりません (claude -h の履歴UIに必須)"; fi
  miss=1
  if command -v brew >/dev/null 2>&1; then INSTALL="brew install python"
  elif command -v apt-get >/dev/null 2>&1; then INSTALL="sudo apt-get update && sudo apt-get install -y python3"
  elif command -v dnf >/dev/null 2>&1; then INSTALL="sudo dnf install -y python3"
  elif command -v pacman >/dev/null 2>&1; then INSTALL="sudo pacman -S --noconfirm python"
  else INSTALL=""; fi
  if [ -n "$INSTALL" ]; then add "      → 導入コマンド: $INSTALL"
  else add "      → お使いの環境のパッケージ管理で python3 を導入してください。"; fi
fi

# git (任意)
if command -v git >/dev/null 2>&1; then add "[OK] git: $(git --version)"
else add "[任意] git は未導入 (git 同期方式を使う場合のみ必要)"; fi

if [ "$QUIET" -eq 1 ] && [ "$miss" -eq 0 ]; then exit 0; fi

echo
echo "== claude-session-sync 環境チェック (macOS / Linux) =="
echo
printf '%s' "$out"
echo

# 不足があり、導入コマンドが分かるなら確認の上で実行
if [ "$miss" -ne 0 ] && [ "${INSTALL:-}" != "" ] && [ "$PYOK" -eq 0 ]; then
  do_it=0
  if [ "$YES" -eq 1 ]; then do_it=1
  else printf 'python3 を今すぐ導入しますか? [y/N] '; read -r ans; case "$ans" in y|Y) do_it=1;; esac; fi
  if [ "$do_it" -eq 1 ]; then
    echo "実行: $INSTALL"
    if eval "$INSTALL"; then echo "導入を試みました。もう一度 check-deps.sh で確認してください。"; else echo "導入に失敗しました。手動で導入してください。"; fi
  fi
fi

if [ "$miss" -eq 0 ]; then echo "すべて揃っています。claude -h(履歴UI)/ claude -a(設定)が使えます。"; exit 0
else echo "上記の[要対応]を解消すると claude -h(履歴UI)が使えます。"; exit 1; fi
