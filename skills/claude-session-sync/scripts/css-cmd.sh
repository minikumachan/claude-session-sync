#!/usr/bin/env bash
#  claude-session-sync : 会話内コマンド ディスパッチャ (macOS / Linux)
#  `/css` スキルから呼ばれる非対話コマンド。CLI 風ボックスで状態/設定を表示し、短いサブコマンドで設定変更(新セッションから反映)。
#  停止必須系(共有/再リンク/復元/MCP取込)は「会話中は不可」を表示。/css gui で設定GUIを別ウィンドウ起動。
#    css-cmd.sh [sub] [a1] [a2]
set -uo pipefail
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"; SCRIPTS="$CLAUDE/skills/claude-session-sync/scripts"
sub="$(printf '%s' "${1:-status}" | tr '[:upper:]' '[:lower:]')"; a1="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"; a2="$(printf '%s' "${3:-}" | tr '[:upper:]' '[:lower:]')"
[ -n "$sub" ] || sub=status
get(){ [ -f "$CFG" ] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
# 値に & | \ 等が含まれても壊れないよう sed 置換をやめ、旧キー行を除去して末尾に追記する。
setkey(){ local k="$1" v="$2" tmp; tmp="$(mktemp)"
  { [ -f "$CFG" ] && grep -vE "^$k=" "$CFG"; printf '%s=%s\n' "$k" "$v"; } > "$tmp" && mv "$tmp" "$CFG"; }
[ -f "$CFG" ] || { echo "未設定です。先に setup を実行してください(claude -a)。"; exit 0; }
onoff(){ [ "$(get "$1")" = off ] && echo OFF || echo ON; }
linkstate(){ if [ -L "$CLAUDE/$1" ]; then echo 共有中; elif [ "$2" = true ]; then echo "設定ON(未リンク)"; else echo ローカル; fi; }
panel(){
  local sync arc rem lang at dn dests
  sync="projects $(linkstate projects "$(get shareProjects)") / skills $(linkstate skills "$(get shareSkills)")"
  dests=""; [ -n "$(get archiveObsidian)" ] && dests="${dests:+$dests / }Obsidian"; [ -n "$(get archiveLocal)" ] && dests="${dests:+$dests / }ローカル"; [ "$(get archiveNotion)" = on ] && dests="${dests:+$dests / }Notion"
  local moc; [ "$(get archiveMoc)" = off ] && moc="OFF(作らない)" || moc=ON
  if [ "$(get archiveEnabled)" = true ]; then arc="ON  → ${dests:-(保存先未設定)}   まとめ:$moc"; else arc=OFF; fi
  if [ "$(get remoteMode)" = all ]; then rem="all (全方式で常にON)"; else rem="items  c:$(onoff remoteC) cfp:$(onoff remoteCfp) ch:$(onoff remoteCh) cc:$(onoff remoteCc)"; fi
  lang="$(get lang)"; [ -z "$lang" ] && lang=auto
  at=$([ "$(get autoTitle)" = false ] && echo OFF || echo ON); dn=$([ "$(get deviceSwitchNotice)" = false ] && echo OFF || echo ON)
  local tn arr md; [ "$(get titleApplyNative)" = off ] && tn=OFF || tn=ON
  onoff2(){ [ "$(get "$1")" = on ] && echo ON || echo OFF; }
  if [ "$(get autoRead)" = on ]; then [ "$(get autoReadMode)" = auto ] && md=自動送信 || md=毎回確認; arr="ON($md)  c:$(onoff2 autoReadC) cfp:$(onoff2 autoReadCfp) cc:$(onoff2 autoReadCc) ch:$(onoff2 autoReadCh)"; else arr=OFF; fi
  local cmp; if [ "$(get compactOnResume)" = on ]; then cmp="ON(再開前に /compact)  cc:$(onoff2 compactCc) ch:$(onoff2 compactCh)"; else cmp=OFF; fi
  cat <<EOF
╭─ Claude セッション同期 ──────────────────────────
│ 同期       ● $sync
│ アーカイブ ● $arc
│ リモート   ● $rem
│ 言語       ● $lang    タイトル自動: $at   ネイティブ名: $tn   切替通知: $dn
│ 自動読込   ● $arr
│ コンパクト ● $cmp
╰──────────────────────────────────────────────────
 操作:  /css archive on|off    /css archive moc on|off    /css remote all|items
        /css remote <c|cfp|ch|cc> on|off
        /css lang <ja|en|zh|…>  /css autotitle on|off  /css devnotice on|off
        /css autoread on|off | mode auto|confirm | <c|cfp|cc|ch> on|off    /css titlenative on|off
        /css compact on|off | <cc|ch> on|off   (再開前に /compact→完了後に開く)
        ※ まとめ索引/自動読込のパス・種別は /css gui で設定
 確認:  /css doctor (環境)   /css mcp (MCP状態)
 GUI :  /css gui  (設定を別ウィンドウで開く=矢印操作)   /css history (履歴UI)
 停止必須(共有/再リンク/復元/MCP取込)は会話中は不可 ⨯ → /css gui か、claude を全終了してターミナルで
EOF
}
blocked(){ cat <<EOF
╭─ 会話中は使用できません ⨯ ────────────────────
│ 「$1」は claude を完全終了してから行う操作です
│ (起動中だと履歴破損・適用漏れの恐れがあるため会話中は実行不可)
╰────────────────────────────────────────────────
 方法: /css gui で設定GUIを別ウィンドウで開く
       または claude を全終了 → ターミナルで claude -a
EOF
}
open_gui(){ local f="$SCRIPTS/$1"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "tell application \"Terminal\" to do script \"bash '$f'\"" >/dev/null 2>&1 && { echo "新しいウィンドウ(Terminal)で開きました(矢印キーで操作)。"; return; }
  fi
  for t in x-terminal-emulator gnome-terminal konsole xterm; do
    if command -v "$t" >/dev/null 2>&1; then ( "$t" -e bash "$f" >/dev/null 2>&1 & ); echo "新しいウィンドウ($t)で開きました(矢印キーで操作)。"; return; fi
  done
  echo "新ウィンドウを開けませんでした。ターミナルで実行してください: bash \"$f\""
}
case "$sub" in
  status|panel|help) panel;;
  archive)
    case "$a1" in
      on) setkey archiveEnabled true; panel;;
      off) setkey archiveEnabled false; panel;;
      moc) case "$a2" in on) setkey archiveMoc on; panel;; off) setkey archiveMoc off; panel;; *) echo '使い方: /css archive moc on|off';; esac;;
      *) echo '使い方: /css archive on|off   または   /css archive moc on|off(まとめ索引の自動作成)';;
    esac;;
  remote)
    case "$a1" in
      all|items) setkey remoteMode "$a1"; panel;;
      c|cfp|ch|cc)
        case "$a2" in
          on|off) case "$a1" in c) k=remoteC;; cfp) k=remoteCfp;; ch) k=remoteCh;; cc) k=remoteCc;; esac; setkey "$k" "$a2"; panel;;
          *) echo '使い方: /css remote c|cfp|ch|cc on|off';;
        esac;;
      *) echo '使い方: /css remote all|items   または   /css remote c|cfp|ch|cc on|off';;
    esac;;
  lang) if [ -n "$a1" ]; then setkey lang "$a1"; setkey titleLang "$a1"; panel; else echo '使い方: /css lang <ja|en|zh|ko|es|fr|de|pt|ru|auto>'; fi;;
  autotitle) case "$a1" in on) setkey autoTitle true; panel;; off) setkey autoTitle false; panel;; *) echo '使い方: /css autotitle on|off';; esac;;
  devnotice) case "$a1" in on) setkey deviceSwitchNotice true; panel;; off) setkey deviceSwitchNotice false; panel;; *) echo '使い方: /css devnotice on|off';; esac;;
  titlenative) case "$a1" in on|off) setkey titleApplyNative "$a1"; panel;; *) echo '使い方: /css titlenative on|off (再開時に日本語タイトルを --name/--remote-control へ適用)';; esac;;
  compact)
    case "$a1" in
      on|off) setkey compactOnResume "$a1"; panel;;
      cc|ch)
        case "$a2" in
          on|off) case "$a1" in cc) k=compactCc;; ch) k=compactCh;; esac; setkey "$k" "$a2"; panel;;
          *) echo '使い方: /css compact cc|ch on|off';;
        esac;;
      *) echo '使い方: /css compact on|off | <cc|ch> on|off (再開前に /compact→完了後に開く)';;
    esac;;
  autoread)
    case "$a1" in
      on|off) setkey autoRead "$a1"; panel;;
      mode) case "$a2" in auto|confirm) setkey autoReadMode "$a2"; panel;; *) echo '使い方: /css autoread mode auto|confirm';; esac;;
      c|cfp|ch|cc)
        case "$a2" in
          on|off) case "$a1" in c) k=autoReadC;; cfp) k=autoReadCfp;; ch) k=autoReadCh;; cc) k=autoReadCc;; esac; setkey "$k" "$a2"; panel;;
          *) echo '使い方: /css autoread c|cfp|cc|ch on|off';;
        esac;;
      *) echo '使い方: /css autoread on|off | mode auto|confirm | <c|cfp|cc|ch> on|off  (パス/種別は /css gui)';;
    esac;;
  doctor) bash "$SCRIPTS/check-deps.sh";;
  mcp) bash "$SCRIPTS/mcp-sync.sh" --status;;
  gui) open_gui autostart-ui.sh;;
  history) open_gui history-ui.sh;;
  share) blocked '共有の開始 / 再リンク';;
  restore) blocked '元の履歴先へ復元';;
  mcp-import) blocked 'MCP の取り込み';;
  *) echo "不明なコマンド: $sub"; echo; panel;;
esac
