#!/usr/bin/env bash
#  claude-session-sync : git トランスポート(同期サービス不要の自己完結同期)  (macOS / Linux)
#    pull / push / status / lock --key K / unlock --key K
#    排他は refs/heads/locks/<key> への一意孤児コミット push(force無し)で実現。
set -uo pipefail
ACTION="${1:-status}"; shift || true
KEY=""; MSG=""
while [[ $# -gt 0 ]]; do case "$1" in
  --key) KEY="$2"; shift 2;;
  --message) MSG="$2"; shift 2;;
  *) shift;;
esac; done

CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "未設定です。setup.sh を先に。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r'; }
[[ "$(get transport)" == "git" ]] || { echo "transport=git ではありません。" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git が見つかりません(git transport に必要)。" >&2; exit 1; }
STORE="$(get store)"
[[ -n "$STORE" && -d "$STORE/.git" ]] || { echo "ストア git リポジトリがありません: $STORE" >&2; exit 1; }
g(){ git -C "$STORE" "$@"; }
HAS_REMOTE=0; [[ -n "$(g remote 2>/dev/null)" ]] && HAS_REMOTE=1

case "$ACTION" in
  status) g remote -v; g status -sb;;
  pull)
    [[ $HAS_REMOTE -eq 1 ]] || { echo "(remote 未設定: pull スキップ)"; exit 0; }
    g fetch -q origin; br="$(g symbolic-ref --short HEAD)"; g merge --no-edit "origin/$br";;
  push)
    g add -A
    if [[ -n "$(g status --porcelain)" ]]; then
      [[ -n "$MSG" ]] || MSG="sync $(hostname) $(date -u +%FT%TZ)"; g commit -q -m "$MSG"
    fi
    [[ $HAS_REMOTE -eq 1 ]] && g push -q origin HEAD || echo "(remote 未設定: ローカル commit のみ)";;
  lock)
    [[ -n "$KEY" ]] || { echo "--key が必要" >&2; exit 1; }
    [[ $HAS_REMOTE -eq 1 ]] || { echo "(remote 未設定: ロック不要)"; exit 0; }
    LR="refs/heads/locks/$KEY"
    tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"   # 既知の空ツリー(全リポジトリ共通)
    commit="$(g commit-tree "$tree" -m "lock machine=$(hostname) user=$USER pid=$$ time=$(date -u +%FT%TZ)")"
    if g push origin "$commit:$LR" >/dev/null 2>&1; then
      echo "🔒 remote lock: $KEY"
    else
      g fetch -q origin "$LR:refs/remotes/origin/_lockpeek" 2>/dev/null || true
      who="$(g log -1 --format='%s' refs/remotes/origin/_lockpeek 2>/dev/null || true)"
      echo "⛔ ロック取得失敗(別デバイスが使用中の可能性): $who" >&2
      exit 2
    fi;;
  unlock)
    [[ -n "$KEY" ]] || { echo "--key が必要" >&2; exit 1; }
    [[ $HAS_REMOTE -eq 1 ]] || exit 0
    g push origin ":refs/heads/locks/$KEY" >/dev/null 2>&1 || true
    echo "🔓 remote unlock: $KEY";;
  *) echo "不明な action: $ACTION" >&2; exit 1;;
esac
