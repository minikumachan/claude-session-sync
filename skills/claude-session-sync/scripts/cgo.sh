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
# titles.map(共有先優先・ローカル fallback)から sid の日本語タイトルを引く。再開時に --name / --remote-control へ渡す。
title_of(){ # $1=sid
  local sid="$1" mp t
  [ -n "$sid" ] || return 0
  for mp in "$(get share)/sessions/titles.map" "$CLAUDE/sessions/titles.map"; do
    [ -f "$mp" ] || continue
    t="$(grep -F "$sid"$'\t' "$mp" 2>/dev/null | head -n1 | cut -f2- | tr -d '\000-\037\177')"   # 共有 titles.map の ESC/制御文字を除去
    [ -n "$t" ] && { printf '%s' "$t"; return 0; }
  done
}
# 再開時コンパクト: master compactOnResume=on + 方式ごと compact<Item>=on(既定 off)。
want_compact(){ # $1=item (Cc/Ch)
  [ "$(get compactOnResume)" = on ] || return 1
  [ "$(get "compact$1")" = on ] || return 1
  return 0
}
# 再開前に /compact を headless 実行し、完了(終了)まで待ってから会話を開く。
run_compact(){ # $1=sid
  [ -n "$1" ] || return 0
  echo ""; echo "  コンパクトを実行中… 完了後に会話を開きます (sid ${1:0:8})"
  "$real" --resume "$1" -p "/compact" --output-format json </dev/null >/dev/null 2>&1 || true
  echo "  コンパクト完了。会話を開きます。"
}
# 自動読み込み: master=autoRead(on)＋方式ごと autoRead<Item>(on)。既定はいずれも off。
want_autoread(){ # $1=item (C/Cfp/Cc)
  [ "$(get autoRead)" = on ] || return 1
  [ "$(get "autoRead$1")" = on ] || return 1
  return 0
}
# 起動時に Claude へ送る「フォルダーを読んで全体像を把握」指示文。パス未設定/不在なら何も出さず非ゼロ。
autoread_instruction(){
  local p kind
  p="$(get autoReadPath)"; [ -n "$p" ] || return 1
  if [ ! -e "$p" ]; then echo "自動読み込み: 指定パスが見つかりません(スキップ): $p" >&2; return 1; fi
  kind="$(get autoReadKind)"; [ -n "$kind" ] || kind="フォルダー"
  printf '%s\n' "作業を始める前に、次の場所の全体像を把握してください。" \
    "場所: $p（$kind）" \
    "フォルダー構成を確認し、_INDEX.md などの索引や主要なノートに目を通して、どこに何があるか・主要なテーマ・運用ルールを理解してください。把握できたら要点を簡潔に報告してください。"
}
# 確認モード: ↑/↓で選択・Enter で決定(既定=送信する)。戻り値 0=送信 / 1=送信しない。
confirm_send(){ # $1=instr
  local instr="$1" sel=0 key k2 k3 ln
  while true; do
    clear; echo
    echo "  起動時に以下を Claude へ送信します:"
    echo "  --------------------------------------------------"
    printf '%s\n' "$instr" | while IFS= read -r ln; do [ -n "$ln" ] && echo "  $ln"; done
    echo; echo "  上記を送信しますか？"
    if [ "$sel" = 0 ]; then echo "   > 送信する"; echo "     送信しない"; else echo "     送信する"; echo "   > 送信しない"; fi
    echo; echo "  ↑/↓ 選択   Enter 決定（Esc/q=送信しない）"
    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\x1b') read -rsn1 -t 1 k2 2>/dev/null || k2=""
               if [ "$k2" = "[" ]; then read -rsn1 -t 1 k3 2>/dev/null || k3=""; case "$k3" in A) sel=0;; B) sel=1;; esac; else return 1; fi ;;
      "")      [ "$sel" = 0 ] && return 0 || return 1 ;;
      q|Q)     return 1 ;;
    esac
  done
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
    want_compact Cc && run_compact "$sid"   # 再開前にコンパクト(完了後に開く)
    cargs+=(--resume "$sid")
    # 再開時は titles.map の日本語タイトルをネイティブ表示名(プロンプト枠/resume)とリモート名に適用
    ttl=""; [ "$(get titleApplyNative)" != off ] && ttl="$(title_of "$sid")"
    [ -n "$ttl" ] && cargs+=(--name "$ttl")
    if want_remote Cc; then if [ -n "$ttl" ]; then cargs+=(--remote-control "$ttl"); else cargs+=(--remote-control); fi; fi
    ;;
  *)                                       # c = 通常起動(現在地)
    want_remote C && cargs+=(--remote-control)
    ;;
esac
# 起動時フォルダ自動読み込み: 方式ごとに有効なら指示文を初回プロンプト(位置引数=最後)として注入。confirm 時は起動前に送信可否を選ぶ。
arprompt=""
case "$MODE" in c) aritem=C;; cfp|cp) aritem=Cfp;; cc) aritem=Cc;; *) aritem="";; esac
if [ -n "$aritem" ] && want_autoread "$aritem"; then
  if instr="$(autoread_instruction)"; then
    if [ "$(get autoReadMode)" = auto ]; then send=0; else confirm_send "$instr"; send=$?; fi
    [ "$send" = 0 ] && arprompt="$instr"
  fi
fi
# 空配列でも set -u で落ちないように展開(macOS の古い bash 3.2 対応)
exec "$real" ${cargs[@]+"${cargs[@]}"} "$@" ${arprompt:+"$arprompt"}
