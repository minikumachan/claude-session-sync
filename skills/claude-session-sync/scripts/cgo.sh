#!/usr/bin/env bash
#  claude-session-sync : 起動ショートカット launcher (macOS / Linux)
#  Mode: c=通常起動(現在地) / cfp,cp=固定パス起動 / cc=直前の会話を再開(全デバイス横断) / ch=履歴UI / ca=設定。
#  conf の launchPath / remoteMode / remoteC / remoteCfp / remoteCc を読む。
#  リモート: remoteMode=all なら全方式で常に付与、それ以外(items)は方式ごとの remote*(既定 ON)。余分な引数は claude へ素通し。
set -uo pipefail
MODE="${1:-c}"; shift 2>/dev/null || true
CLAUDE="$HOME/.claude"; SCRIPTS="$CLAUDE/skills/claude-session-sync/scripts"; CFG="$CLAUDE/session-sync.local.conf"
get(){ [ -f "$CFG" ] && grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r' || true; }
want_remote(){ # $1 = item suffix (C / Cfp / Cc)
  [ "$(get remoteMode)" = "all" ] && return 0
  [ "$(get "remote$1")" != "off" ] && return 0 || return 1
}

case "$MODE" in
  ch) exec bash "$SCRIPTS/history-ui.sh" ;;
  ca) exec bash "$SCRIPTS/autostart-ui.sh" ;;
esac

# 実体 claude(css-bin の shim を除外して PATH から解決)
self="$HOME/.claude/css-bin"; real=""
oldifs="$IFS"; IFS=:
for d in $PATH; do
  [ "$d" = "$self" ] && continue
  if [ -f "$d/claude" ] && [ -x "$d/claude" ]; then real="$d/claude"; break; fi
done
IFS="$oldifs"
[ -n "$real" ] || { echo "real claude が見つかりません(npm 等で導入してください)。" >&2; exit 1; }

cargs=()
case "$MODE" in
  cfp|cp)                                  # 固定パス起動(cp は cfp の別名・remoteCfp を共有)
    lp="$(get launchPath)"
    if [ -n "$lp" ] && [ -d "$lp" ]; then cd "$lp" || true
    else echo "固定パス起動の場所が未設定/不在です。『claude -a』→ 起動ショートカット設定 で設定してください。" >&2; fi
    want_remote Cfp && cargs+=(--remote-control)
    ;;
  cc)                                      # 直前の会話を再開(全デバイス横断=同期済 projects 全体で最新)
    pj="$CLAUDE/projects"
    newest=""; newest_t=-1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      t="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)"; [ -n "$t" ] || continue
      if [ "$t" -gt "$newest_t" ] 2>/dev/null; then newest_t="$t"; newest="$f"; fi
    done < <(find "$pj" -name '*.jsonl' -type f 2>/dev/null | grep -v session-sync-titlegen)
    [ -n "$newest" ] || { echo "再開できる会話が見つかりません。" >&2; exit 1; }
    sid="$(basename "$newest" .jsonl)"
    cargs+=(--resume "$sid")
    want_remote Cc && cargs+=(--remote-control)
    ;;
  *)                                       # c = 通常起動(現在地)
    want_remote C && cargs+=(--remote-control)
    ;;
esac
# 空配列でも set -u で落ちないように展開(macOS の古い bash 3.2 対応)
exec "$real" ${cargs[@]+"${cargs[@]}"} "$@"
