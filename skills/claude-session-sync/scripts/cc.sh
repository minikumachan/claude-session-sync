#!/usr/bin/env bash
#  claude-session-sync : ロック付きで Claude を起動 (macOS / Linux)
#    transport=folder … 共有フォルダ内のロックファイル(原子的作成) / transport=git … pull+リモートロック→終了時 push+解除
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[[ -f "$CFG" ]] || { echo "未設定です。先に setup.sh を実行してください。" >&2; exit 1; }
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }   # CRLF 混入に強く
encode(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCOPE="$(get lockScope)"; [[ -z "$SCOPE" ]] && SCOPE=project
TRANSPORT="$(get transport)"; [[ -z "$TRANSPORT" ]] && TRANSPORT=folder
KEY="ACTIVE"; [[ "$SCOPE" == "project" ]] && KEY="$(encode "$(pwd)")"

FORCE=0; UNLOCK=0; ARGS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --force) FORCE=1; shift;;
  --unlock) UNLOCK=1; shift;;
  *) ARGS+=("$1"); shift;;
esac; done

# ===== git transport =====
if [[ "$TRANSPORT" == "git" ]]; then
  if [[ $UNLOCK -eq 1 ]]; then bash "$DIR/sync.sh" unlock --key "$KEY"; exit 0; fi
  command -v git >/dev/null 2>&1 || { echo "git が見つかりません(git transport に必要)。" >&2; exit 1; }
  command -v claude >/dev/null 2>&1 || { echo "claude が見つかりません。Claude Code を導入し PATH を確認してください。" >&2; exit 1; }
  bash "$DIR/sync.sh" pull || true
  if ! bash "$DIR/sync.sh" lock --key "$KEY"; then
    if [[ $FORCE -ne 1 ]]; then
      echo "   解決: もう一方で終了 / 残骸なら cc.sh --unlock(または sync.sh unlock --key $KEY)で解除。" >&2
      exit 1
    fi
    echo "⚠ --force: 既存リモートロックを解除して取得し直します。"
    bash "$DIR/sync.sh" unlock --key "$KEY"
    bash "$DIR/sync.sh" lock --key "$KEY" || { echo "⛔ 取得できません。中止。" >&2; exit 1; }
  fi
  cleanup(){ bash "$DIR/sync.sh" push --message "session end $(hostname) $(date -u +%FT%TZ)" || true; bash "$DIR/sync.sh" unlock --key "$KEY" || true; }
  trap cleanup EXIT
  command claude "${ARGS[@]}"
  exit 0
fi

# ===== folder transport (file lock) =====
command -v claude >/dev/null 2>&1 || { echo "claude が見つかりません。Claude Code を導入し PATH を確認してください。" >&2; exit 1; }
SHARE="$(get share)"; [[ -n "$SHARE" ]] || { echo "config に share がありません。" >&2; exit 1; }
LOCKDIR="$SHARE/locks"; mkdir -p "$LOCKDIR"
LOCK="$LOCKDIR/$KEY.lock"
if [[ $UNLOCK -eq 1 ]]; then
  if [[ -f "$LOCK" ]]; then rm -f "$LOCK"; echo "🔓 解除: $KEY"; else echo "ロックなし: $KEY"; fi; exit 0
fi
CONTENT="machine=$(hostname) user=$USER pid=$$ scope=$SCOPE key=$KEY start=$(date -u +%FT%TZ)"
# 原子的に作成(noclobber: 既存なら失敗)。TOCTOU 競合を回避。
if ! ( set -o noclobber; printf '%s\n' "$CONTENT" > "$LOCK" ) 2>/dev/null; then
  if [[ $FORCE -ne 1 ]]; then
    echo "⛔ このプロジェクト/セッションは使用中の可能性: $(cat "$LOCK" 2>/dev/null)" >&2
    echo "   解決: もう一方で終了 / 残骸なら --force / 強制解除は cc.sh --unlock" >&2
    exit 1
  fi
  echo "⚠ --force: 既存ロックを上書き → $(cat "$LOCK" 2>/dev/null)"
  rm -f "$LOCK"; ( set -o noclobber; printf '%s\n' "$CONTENT" > "$LOCK" ) 2>/dev/null || { echo "⛔ ロック作成失敗。" >&2; exit 1; }
fi
echo "🔒 lock: $KEY"
cleanup(){ if [[ -f "$LOCK" ]] && grep -q "pid=$$\b" "$LOCK"; then rm -f "$LOCK"; echo "🔓 unlock: $KEY"; fi; }
trap cleanup EXIT
command claude "${ARGS[@]}"
