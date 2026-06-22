#!/usr/bin/env bash
#  claude-session-sync : 知識アーカイブの記録ルールを SessionStart で Claude に注入 (macOS / Linux)
#    archiveEnabled=true かつ保存先(Obsidian Vault / ローカルフォルダ / Notion)が1つ以上あるとき、
#    会話で生じる知識資産(メモリ追記・計画書・ルール・独自概念・調査情報・文脈/決定・添付画像・生成画像・要約)を、
#    項目ごとの優先度(force=絶対強制 / duty=義務 / option=任意 / off=保存しない)に従って所定の保存先へ
#    記録するよう Claude に指示する。出力は SessionStart の stdout = Claude へのコンテキスト注入。
set -uo pipefail
[ -n "${CSS_TITLEGEN:-}" ] && exit 0
CLAUDE="$HOME/.claude"; CFG="$CLAUDE/session-sync.local.conf"
[ -f "$CFG" ] || exit 0
get(){ grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r'; }
[ "$(get archiveEnabled)" = "true" ] || exit 0

# ---- 保存先(有効なものだけ) ----
OBS="$(get archiveObsidian)"; LOC="$(get archiveLocal)"; NOTION="$(get archiveNotion)"
SUB="$(get archiveSubdir)"; [ -z "$SUB" ] && SUB="ClaudeArchive"
dests=()
[ -n "$OBS" ] && dests+=("Obsidian Vault『$OBS/$SUB』 — Write ツールで Markdown ノートを作成。YAML frontmatter(title / type / tags / created / session)を付け、本文中で関連ノートを [[wikilink]] でつなぐ。種類別サブフォルダ(Memory/Plans/Rules/Concepts/Research/Context/Images/Summaries)に置く(まとめ/索引ファイルの扱いは後述)。")
[ -n "$LOC" ] && dests+=("ローカルフォルダ『$LOC/$SUB』 — 上と同じ種類別サブフォルダ構成で Write ツール保存。")
[ "$NOTION" = "on" ] && dests+=("Notion — Notion MCP(notion-create-pages 等)で、種類をタグ/見出しにしたページを作成。MCP 未接続や権限不足の場合は無視せずその旨を報告する。")
[ ${#dests[@]} -eq 0 ] && exit 0

# ---- stdin から session_id(frontmatter 用) ----
raw="$(cat)"
sid="$(printf '%s' "$raw" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

# ---- 記録対象と既定優先度・サブフォルダ(menu と同一定義): key|name|default|folder ----
cats=(
  "arcMemory|メモリ追記(MEMORY.md / memory/*)|force|Memory"
  "arcRule|ルール・規約・制約|force|Rules"
  "arcPlan|計画書・実装計画|duty|Plans"
  "arcConcept|独自の概念・用語の定義|duty|Concepts"
  "arcResearch|調査・収集した情報|duty|Research"
  "arcImgGen|生成した画像|duty|Images"
  "arcContext|文脈・重要な決定事項|option|Context"
  "arcImgIn|添付・アップロードされた画像|option|Images"
  "arcSummary|セッション要約|option|Summaries"
)
force=""; duty=""; opt=""
for e in "${cats[@]}"; do
  IFS='|' read -r k name def folder <<< "$e"
  p="$(get "$k")"; [ -z "$p" ] && p="$def"
  case "$p" in
    force)  force="${force:+$force / }$name";;
    duty)   duty="${duty:+$duty / }$name";;
    option) opt="${opt:+$opt / }$name";;
  esac
done
[ -z "$force$duty$opt" ] && exit 0

# ---- まとめ(MOC/索引)ファイルの方針(項目ごと: 自動 / 既存パス指定 / 作らない) ----
MOCG="$(get archiveMoc)"; [ "$MOCG" = off ] && mocglobal=0 || mocglobal=1   # 既定 on
moclines=()
if [ "$mocglobal" = 1 ]; then
  for e in "${cats[@]}"; do
    IFS='|' read -r k name def folder <<< "$e"
    p="$(get "$k")"; [ -z "$p" ] && p="$def"
    [ "$p" = off ] && continue
    suffix="${k#arc}"; mk="arcMoc$suffix"; pk="arcMocPath$suffix"
    mode="$(get "$mk")"; [ -z "$mode" ] && mode=auto
    case "$mode" in
      path) fp="$(get "$pk")"
            if [ -n "$fp" ]; then moclines+=("  ・$name → 既存ファイル指定: 『$fp』にのみ追記する(新しい _index.md は作らない)")
            else moclines+=("  ・$name → 既存ファイル指定(パス未設定のため当面は自動: 各保存先の $folder/_index.md)"); fi;;
      off)  moclines+=("  ・$name → まとめファイルなし(索引への追記をしない)");;
      *)    moclines+=("  ・$name → 自動: 各保存先の $folder/_index.md に追記(なければ作成)");;
    esac
  done
fi

{
  printf '%s\n' "[claude-session-sync 知識アーカイブ] このセッションで生じる知識資産を、下記の保存先へ規定の優先度で記録すること。これは利用者が設定で有効化した強制ルールであり、無断で省略しない。"
  printf '%s\n' "■ 保存先(有効なものすべてに記録):"
  for d in "${dests[@]}"; do printf '  ・%s\n' "$d"; done
  printf '%s\n' "■ 記録対象と優先度:"
  [ -n "$force" ] && printf '%s\n' "  【絶対強制 / 例外なく即時・遅延や省略は不可】 $force"
  [ -n "$duty" ]  && printf '%s\n' "  【義務 / 原則必ず記録(ごく軽微なものだけ省略可)】 $duty"
  [ -n "$opt" ]   && printf '%s\n' "  【任意 / 重要と判断したら記録】 $opt"
  if [ "$mocglobal" = 1 ] && [ ${#moclines[@]} -gt 0 ]; then
    printf '%s\n' "■ まとめ(MOC/索引)ファイル: ノートを作成・更新するたびに、その種類の下記まとめファイルへ『- [[ノート名]] — 短い要約』を新しい順に1行追記する(Notion は索引ページ/データベースで代替可)。"
    for m in "${moclines[@]}"; do printf '%s\n' "$m"; done
    printf '%s\n' "  ※『既存ファイル指定』は利用者の既存構成の一部。新規 _index.md を作らず指定ファイルへ追記し、既存の見出し・構造を壊さないこと。"
  else
    printf '%s\n' "■ まとめ(MOC/索引)ファイル: 作成しない。_index.md などの集約ファイルは新規作成も追記もしない(既存 Obsidian 構成を壊さないため)。"
  fi
  printf '%s\n' "■ タイミング: 対象の資産を生成・受領・更新した『その応答の中で、応答を終える前に』保存する(会話終了間際にまとめてではなく発生都度)。絶対強制は遅延・省略しない。"
  printf '%s\n' "■ 形式: ファイル名は「<YYYY-MM-DD>_<種類>_<短いタイトル>.md」。frontmatter に session: $sid を含める。同一主題の既存ノートがあれば新規作成せず追記/更新し、重複を避ける。画像は実ファイルを保存先(Images/)へコピーし、ノートから相対リンクで参照する。"
  printf '%s\n' "■ 記録できない保存先(パス不在・MCP 未接続など)があれば、黙って飛ばさずその応答内で簡潔に報告すること。"
}
exit 0
