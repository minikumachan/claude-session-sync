<#  claude-session-sync : 全プロジェクト横断の履歴ビューア (Windows)
    どのカレントディレクトリからでも全履歴を一覧/閲覧/再開。~/.claude/projects を直接読む。
    - デバイス(由来マシン)を色＋ラベルで表示(同機種は device map で識別)
    - タイトル: 言語固定の生成タイトル(titles.map) > Claude の ai-title > 冒頭発話
      list  [-Limit N] [-Grep 語] [-Device 名]   一覧(既定 -Limit 40)
      view  <#|id>                               会話本文
      resume <#|id>                              現フォルダに取り込み再開
      title [-Limit N|-All|-Id <#|id>]           会話内容から固定言語のタイトルを生成しキャッシュ
      path  <#|id>                               .jsonl パス  #>
[CmdletBinding()]
param(
  [Parameter(Position=0)][ValidateSet('list','view','resume','title','path')][string]$Command='list',
  [Parameter(Position=1)][string]$Id,
  [int]$Page=1,
  [int]$PageSize=20,
  [int]$Limit=40,
  [string]$Grep,
  [string]$Device,
  [switch]$All
)
$ErrorActionPreference='Stop'
$claude   = Join-Path $env:USERPROFILE '.claude'
$projects = Join-Path $claude 'projects'
if(-not (Test-Path $projects)){ throw "履歴フォルダがありません: $projects" }
$cfgPath = Join-Path $claude 'session-sync.local.conf'
$cfg=@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){$cfg[$matches[1]]=($matches[2].TrimEnd("`r"))} } }
$lang = if($cfg.lang){ $cfg.lang } else { 'en' }

# 共有サイドカー: device map / titles map (sessionId<TAB>値)。share 配下。
$devMap=@{}; $titleMap=@{}; $titlesPath=$null
if($cfg.share){
  $dm = Join-Path $cfg.share 'sessions\devices.map'
  if(Test-Path $dm){ foreach($l in (Get-Content $dm -Encoding utf8 -EA SilentlyContinue)){ $p=$l -split "`t",2; if($p.Count -eq 2){ $devMap[$p[0]]=$p[1] } } }
  $titlesPath = Join-Path $cfg.share 'sessions\titles.map'
  if(Test-Path $titlesPath){ foreach($l in (Get-Content $titlesPath -Encoding utf8 -EA SilentlyContinue)){ $p=$l -split "`t",2; if($p.Count -eq 2){ $titleMap[$p[0]]=$p[1] } } }
}

function Get-Sessions {
  Get-ChildItem $projects -Recurse -Filter *.jsonl -EA SilentlyContinue | Where-Object {
    (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
    $_.BaseName -notlike 'agent-*' -and $_.BaseName -ne 'journal'
  } | Sort-Object LastWriteTime -Descending
}
function MsgText($o){
  $c=$o.message.content; if($null -eq $c){return ''}
  if($c -is [string]){return $c}
  $p=@(); foreach($b in $c){ if($b.type -eq 'text' -and $b.text){ $p+=$b.text } }
  ($p -join "`n")
}
function DeviceFromCwd([string]$cwd){
  if(-not $cwd){ return 'unknown' }
  if($cwd -match '^[A-Za-z]:\\'){ $u = if($cwd -match '^[A-Za-z]:\\Users\\([^\\]+)'){$matches[1]}else{'?'}; return "Win/$u" }
  if($cwd -match '^/Users/([^/]+)'){ return "Mac/$($matches[1])" }
  if($cwd -match '^/home/([^/]+)'){ return "Linux/$($matches[1])" }
  if($cwd -match '^/root'){ return "Linux/root" }
  return 'unknown'
}
# 1パスで cwd / ai-title / 最初のユーザー発話 を取得
function Scan($f){
  $cwd=''; $prev=''; $ai=''
  foreach($line in (Get-Content $f -Encoding utf8 -EA SilentlyContinue | Select-Object -First 120)){
    if(-not $line.Trim()){continue}
    try{$o=$line|ConvertFrom-Json}catch{continue}
    if(-not $cwd -and $o.cwd){ $cwd=[string]$o.cwd }
    if(-not $ai  -and $o.type -eq 'ai-title' -and $o.aiTitle){ $ai=[string]$o.aiTitle }
    if(-not $prev -and $o.message.role -eq 'user'){ $t=MsgText $o; if($t){ $prev=($t -replace '\s+',' ').Trim() } }
    if($cwd -and $prev -and $ai){ break }
  }
  [pscustomobject]@{ cwd=$cwd; preview=$prev; ai=$ai }
}
$palette=@('Cyan','Green','Yellow','Magenta','Blue','Red','DarkCyan','DarkGreen','DarkYellow','DarkMagenta','White')
function ColorFor([string]$dev){ $h=0; foreach($ch in $dev.ToCharArray()){ $h=($h*31+[int]$ch) }; $palette[[Math]::Abs($h)%$palette.Count] }
function DeviceLabel($sid,$cwd){ if($devMap.ContainsKey($sid)){ return $devMap[$sid] } else { return (DeviceFromCwd $cwd) } }
function TitleOf($sid,$s){ if($titleMap.ContainsKey($sid)){ return $titleMap[$sid] } elseif($s.ai){ return $s.ai } elseif($s.preview){ return $s.preview } else { return '(無題)' } }
function Find-File($key){
  $all=@(Get-Sessions)
  if($key -match '^\d+$' -and [int]$key -ge 1 -and [int]$key -le $all.Count){ return $all[[int]$key-1] }
  $all | Where-Object { $_.BaseName -eq $key -or $_.BaseName -like "$key*" } | Select-Object -First 1
}

switch($Command){
 'list'{
   # ページ式: 現ページ分だけ Scan(高速)。# はソート済み全体の通し番号。
   $allS=@(Get-Sessions); $total=$allS.Count   # ※ $all は switch の $All と同名衝突するため使わない
   if($PageSize -lt 1){ $PageSize=20 }
   $pages=[Math]::Max(1,[int][Math]::Ceiling($total/$PageSize))
   if($Page -lt 1){ $Page=1 }; if($Page -gt $pages){ $Page=$pages }
   $start=($Page-1)*$PageSize
   $slice=@($allS | Select-Object -Skip $start -First $PageSize)
   $seenDev=@{}; $idx=$start
   Write-Host ("ページ {0}/{1}  (全 {2} 件 / 1ページ {3} 件)" -f $Page,$pages,$total,$PageSize) -ForegroundColor Cyan
   Write-Host ("{0,4}  {1,-11}  {2,-12}  {3}" -f '#','Updated','Device','Title') -ForegroundColor DarkGray
   foreach($f in $slice){
     $idx++; $s=Scan $f.FullName; $dev=DeviceLabel $f.BaseName $s.cwd
     if($Device -and ($dev -notmatch [regex]::Escape($Device))){ continue }
     $title=TitleOf $f.BaseName $s; $projName=Split-Path $f.DirectoryName -Leaf
     if($Grep -and ($title -notmatch [regex]::Escape($Grep)) -and ($projName -notmatch [regex]::Escape($Grep))){ continue }
     $seenDev[$dev]=$true
     $up=$f.LastWriteTime.ToString('MM-dd HH:mm')
     $ttl=if($title.Length -gt 64){ $title.Substring(0,63)+'…' }else{ $title }
     Write-Host ("{0,4}  {1,-11}  " -f $idx,$up) -NoNewline
     Write-Host ("{0,-12}" -f $dev) -ForegroundColor (ColorFor $dev) -NoNewline
     Write-Host ("  {0}" -f $ttl)
   }
   Write-Host ""
   Write-Host "凡例: " -NoNewline -ForegroundColor DarkGray
   foreach($d in ($seenDev.Keys|Sort-Object)){ Write-Host "$d " -NoNewline -ForegroundColor (ColorFor $d) }
   Write-Host ""
   $nav=@(); if($Page -lt $pages){ $nav+="次ページ: -Page $($Page+1)" }; if($Page -gt 1){ $nav+="前: -Page $($Page-1)" }
   Write-Host (($nav -join ' / ')+"  / 1ページ件数: -PageSize N / 閲覧: view <#> / 再開: resume <#>") -ForegroundColor DarkGray
 }
 'view'{
   if(-not $Id){ throw "番号またはIDを指定してください。" }
   $f=Find-File $Id; if(-not $f){ throw "見つかりません: $Id" }
   $s=Scan $f.FullName; $dev=DeviceLabel $f.BaseName $s.cwd
   Write-Host "=== $(TitleOf $f.BaseName $s) ===" -ForegroundColor Cyan
   Write-Host "$($f.BaseName)  " -NoNewline -ForegroundColor DarkGray
   Write-Host "[$dev]" -NoNewline -ForegroundColor (ColorFor $dev)
   Write-Host "  $(Split-Path $f.DirectoryName -Leaf)  $($f.LastWriteTime)  cwd=$($s.cwd)" -ForegroundColor DarkGray
   foreach($line in (Get-Content $f.FullName -Encoding utf8)){
     if(-not $line.Trim()){continue}; try{$o=$line|ConvertFrom-Json}catch{continue}
     $role=$o.message.role; if($role -ne 'user' -and $role -ne 'assistant'){continue}
     $t=MsgText $o; if(-not $t){continue}
     Write-Host "`n[$role]" -ForegroundColor $(if($role -eq 'user'){'Green'}else{'Cyan'}); Write-Host $t
   }
 }
 'title'{
   if(-not $titlesPath){ throw "共有(share)が未設定のため titles.map を保存できません。setup を実行してください。" }
   $realClaude = (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source
   if(-not $realClaude){ throw "claude が見つかりません(タイトル生成に必要)。" }
   $targets = if($Id){ @(Find-File $Id) } elseif($All){ @(Get-Sessions) } else { @(Get-Sessions) | Select-Object -First $Limit }
   $made=0
   foreach($f in $targets){
     if(-not $f){ continue }
     $sid=$f.BaseName
     if($titleMap.ContainsKey($sid)){ continue }   # 既に生成済みはスキップ
     $s=Scan $f.FullName
     $seed = if($s.ai){ $s.ai } else { $s.preview }
     if(-not $seed){ continue }
     $excerpt = $seed.Substring(0,[Math]::Min(500,$seed.Length))
     $prompt = "Create a concise, descriptive title (max 8 words) for this conversation. Respond ONLY with the title text, in language code '$lang'. Conversation start: $excerpt"
     try {
       $t = (& $realClaude -p $prompt 2>$null | Out-String).Trim()
       $t = ($t -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
       $t = $t.Trim('"','「','」',' ')
       if($t){ $line = "$sid`t$t"; Add-Content -Path $titlesPath -Value $line -Encoding utf8; $titleMap[$sid]=$t; $made++; Write-Host "✔ $($sid.Substring(0,8))  $t" -ForegroundColor Green }
     } catch { Write-Host "× $($sid.Substring(0,8)) 生成失敗" -ForegroundColor Yellow }
   }
   Write-Host "`n生成: $made 件(言語=$lang)。history list で反映されます。" -ForegroundColor Cyan
 }
 'path'{ if(-not $Id){ throw "番号/IDを指定してください。" }; $f=Find-File $Id; if($f){ $f.FullName } else { throw "見つかりません: $Id" } }
}
