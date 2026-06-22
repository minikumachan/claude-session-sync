<#  claude-session-sync : 知識アーカイブの記録ルールを SessionStart で Claude に注入 (Windows)
    archiveEnabled=true かつ保存先(Obsidian Vault / ローカルフォルダ / Notion)が
    1つ以上あるとき、会話で生じる知識資産(メモリ追記・計画書・ルール・独自概念・
    調査情報・文脈/決定・添付画像・生成画像・要約)を、項目ごとの優先度
    (force=絶対強制 / duty=義務 / option=任意 / off=保存しない)に従って
    所定の保存先へ記録するよう Claude に指示する。
    出力は SessionStart の stdout = Claude へのコンテキスト注入。  #>
$ErrorActionPreference = 'SilentlyContinue'
if($env:CSS_TITLEGEN){ exit 0 }
# フック出力は Claude が UTF-8 で読む。WinPS5.1 既定(CP932)で化けないよう UTF-8 バイト列を直接書く。
function CssEmit([string]$s){
  try{ $b=[System.Text.Encoding]::UTF8.GetBytes($s+"`n"); $o=[System.Console]::OpenStandardOutput(); $o.Write($b,0,$b.Length); $o.Flush() }
  catch{ Write-Output $s }
}
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ exit 0 }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
if(($cfg['archiveEnabled']) -ne 'true'){ exit 0 }

# ---- 保存先(有効なものだけ) ----
$obs = $cfg['archiveObsidian']; $loc = $cfg['archiveLocal']; $notion = ($cfg['archiveNotion'] -eq 'on')
$sub = if($cfg['archiveSubdir']){ $cfg['archiveSubdir'] } else { 'ClaudeArchive' }
$dests=@()
if($obs){ $dests += "Obsidian Vault『$obs\$sub』 — Write ツールで Markdown ノートを作成。YAML frontmatter(title / type / tags / created / session)を付け、本文中で関連ノートを [[wikilink]] でつなぐ。種類別サブフォルダ(Memory/Plans/Rules/Concepts/Research/Context/Images/Summaries)に置く(まとめ/索引ファイルの扱いは後述)。" }
if($loc){ $dests += "ローカルフォルダ『$loc\$sub』 — 上と同じ種類別サブフォルダ構成で Write ツール保存。" }
if($notion){ $dests += "Notion — Notion MCP(notion-create-pages 等)で、種類をタグ/見出しにしたページを作成。MCP 未接続や権限不足の場合は無視せずその旨を報告する。" }
if($dests.Count -eq 0){ exit 0 }

# ---- stdin から session_id(frontmatter 用) ----
$sid=''
try{
  $reader = New-Object System.IO.StreamReader([System.Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
  $raw = $reader.ReadToEnd(); $reader.Dispose()
  if($raw){ $j = $raw | ConvertFrom-Json; if($j.session_id){ $sid=$j.session_id } }
}catch{}

# ---- 記録対象と既定優先度・サブフォルダ(menu と同一定義): name / priority / folder ----
$cats=[ordered]@{
  arcMemory   = @('メモリ追記(MEMORY.md / memory/*)','force','Memory')
  arcRule     = @('ルール・規約・制約','force','Rules')
  arcPlan     = @('計画書・実装計画','duty','Plans')
  arcConcept  = @('独自の概念・用語の定義','duty','Concepts')
  arcResearch = @('調査・収集した情報','duty','Research')
  arcImgGen   = @('生成した画像','duty','Images')
  arcContext  = @('文脈・重要な決定事項','option','Context')
  arcImgIn    = @('添付・アップロードされた画像','option','Images')
  arcSummary  = @('セッション要約','option','Summaries')
}
$force=@(); $duty=@(); $opt=@()
foreach($k in $cats.Keys){
  $name=$cats[$k][0]; $def=$cats[$k][1]
  $p = if($cfg.ContainsKey($k) -and $cfg[$k]){ $cfg[$k] } else { $def }
  switch($p){ 'force'{ $force+=$name } 'duty'{ $duty+=$name } 'option'{ $opt+=$name } default{} }
}
if(($force.Count+$duty.Count+$opt.Count) -eq 0){ exit 0 }

# ---- まとめ(MOC/索引)ファイルの方針(項目ごと: 自動作成 / 既存パス指定 / 作らない) ----
$mocGlobal = (($cfg['archiveMoc']) -ne 'off')   # 既定 on
$mocLines=@()
if($mocGlobal){
  foreach($k in $cats.Keys){
    $name=$cats[$k][0]; $def=$cats[$k][1]; $folder=$cats[$k][2]
    $p = if($cfg.ContainsKey($k) -and $cfg[$k]){ $cfg[$k] } else { $def }
    if($p -eq 'off'){ continue }                                    # 記録しない種類は MOC 不要
    $mk = $k -replace '^arc','arcMoc'; $pk = $k -replace '^arc','arcMocPath'
    $mode = if($cfg.ContainsKey($mk) -and $cfg[$mk]){ $cfg[$mk] } else { 'auto' }
    switch($mode){
      'path' {
        $fp = $cfg[$pk]
        if($fp){ $mocLines += "  ・$name → 既存ファイル指定: 『$fp』にのみ追記する(新しい _index.md は作らない)" }
        else   { $mocLines += "  ・$name → 既存ファイル指定(パス未設定のため当面は自動: 各保存先の $folder/_index.md)" }
      }
      'off'  { $mocLines += "  ・$name → まとめファイルなし(索引への追記をしない)" }
      default{ $mocLines += "  ・$name → 自動: 各保存先の $folder/_index.md に追記(なければ作成)" }
    }
  }
}

$lines=@()
$lines += "[claude-session-sync 知識アーカイブ] このセッションで生じる知識資産を、下記の保存先へ規定の優先度で記録すること。これは利用者が設定で有効化した強制ルールであり、無断で省略しない。"
$lines += "■ 保存先(有効なものすべてに記録):"
foreach($d in $dests){ $lines += "  ・$d" }
$lines += "■ 記録対象と優先度:"
if($force.Count){ $lines += "  【絶対強制 / 例外なく即時・遅延や省略は不可】 " + ($force -join ' / ') }
if($duty.Count){  $lines += "  【義務 / 原則必ず記録(ごく軽微なものだけ省略可)】 " + ($duty -join ' / ') }
if($opt.Count){   $lines += "  【任意 / 重要と判断したら記録】 " + ($opt -join ' / ') }
if($mocGlobal -and $mocLines.Count){
  $lines += "■ まとめ(MOC/索引)ファイル: ノートを作成・更新するたびに、その種類の下記まとめファイルへ『- [[ノート名]] — 短い要約』を新しい順に1行追記する(Notion は索引ページ/データベースで代替可)。"
  $lines += $mocLines
  $lines += "  ※『既存ファイル指定』は利用者の既存構成の一部。新規 _index.md を作らず指定ファイルへ追記し、既存の見出し・構造を壊さないこと。"
} else {
  $lines += "■ まとめ(MOC/索引)ファイル: 作成しない。_index.md などの集約ファイルは新規作成も追記もしない(既存 Obsidian 構成を壊さないため)。"
}
$lines += "■ タイミング: 対象の資産を生成・受領・更新した『その応答の中で、応答を終える前に』保存する(会話終了間際にまとめてではなく発生都度)。絶対強制は遅延・省略しない。"
$lines += "■ 形式: ファイル名は「<YYYY-MM-DD>_<種類>_<短いタイトル>.md」。frontmatter に session: $sid を含める。同一主題の既存ノートがあれば新規作成せず追記/更新し、重複を避ける。画像は実ファイルを保存先(Images/)へコピーし、ノートから相対リンクで参照する。"
$lines += "■ 記録できない保存先(パス不在・MCP 未接続など)があれば、黙って飛ばさずその応答内で簡潔に報告すること。"
CssEmit ($lines -join "`n")
exit 0
