<#  claude-session-sync : 全プロジェクト横断の履歴ビューア (Windows)
    どのカレントディレクトリからでも、全プロジェクトの会話履歴を一覧/閲覧/再開できる。
    ~/.claude/projects(= 共有先へのリンク先)を直接読むため、パスに依存しない。
      list           : 全履歴を新しい順で一覧(プロジェクト・日時・冒頭プレビュー)
      view  <#|id>   : 指定セッションの会話本文を表示
      resume <#|id>  : 現在のフォルダに取り込み、claude --resume コマンドを表示
      path  <#|id>   : 元 .jsonl の絶対パスを表示
    例: history.ps1 list  /  history.ps1 list -Grep 同期  /  history.ps1 view 3  #>
[CmdletBinding()]
param(
  [Parameter(Position=0)][ValidateSet('list','view','resume','path')][string]$Command='list',
  [Parameter(Position=1)][string]$Id,
  [int]$Limit=60,
  [string]$Grep
)
$ErrorActionPreference='Stop'
$projects = Join-Path $env:USERPROFILE '.claude\projects'
if(-not (Test-Path $projects)){ throw "履歴フォルダがありません: $projects" }

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
function FirstUser($f){
  foreach($line in (Get-Content $f -Encoding utf8 -EA SilentlyContinue)){
    if(-not $line.Trim()){continue}
    try{$o=$line|ConvertFrom-Json}catch{continue}
    if($o.message.role -eq 'user'){ $t=MsgText $o; if($t){ return (($t -replace '\s+',' ').Trim()) } }
  }
  ''
}
function Find-File($key){
  $all=@(Get-Sessions)
  if($key -match '^\d+$' -and [int]$key -ge 1 -and [int]$key -le $all.Count){ return $all[[int]$key-1] }
  $all | Where-Object { $_.BaseName -eq $key -or $_.BaseName -like "$key*" } | Select-Object -First 1
}

switch($Command){
 'list'{
   $i=0; $rows=@()
   foreach($f in (@(Get-Sessions) | Select-Object -First $Limit)){
     $i++; $prev=FirstUser $f.FullName; $projName=Split-Path $f.DirectoryName -Leaf
     if($Grep -and ($prev -notmatch [regex]::Escape($Grep)) -and ($projName -notmatch [regex]::Escape($Grep))){ continue }
     $rows += [pscustomobject]@{
       '#'=$i; Updated=$f.LastWriteTime.ToString('MM-dd HH:mm'); KB=[math]::Round($f.Length/1KB)
       Project=$projName; Session=$f.BaseName.Substring(0,[Math]::Min(8,$f.BaseName.Length))
       Preview=($prev.Substring(0,[Math]::Min(60,$prev.Length)))
     }
   }
   if(-not $rows){ Write-Host "履歴が見つかりません。" -ForegroundColor Yellow; return }
   $rows | Format-Table -AutoSize -Wrap
   Write-Host "閲覧: history.ps1 view <#|id> / 再開: history.ps1 resume <#|id>" -ForegroundColor DarkGray
 }
 'view'{
   if(-not $Id){ throw "セッション番号またはIDを指定してください。" }
   $f=Find-File $Id; if(-not $f){ throw "見つかりません: $Id" }
   Write-Host "=== $($f.BaseName)  [$(Split-Path $f.DirectoryName -Leaf)]  $($f.LastWriteTime) ===" -ForegroundColor Cyan
   foreach($line in (Get-Content $f.FullName -Encoding utf8)){
     if(-not $line.Trim()){continue}; try{$o=$line|ConvertFrom-Json}catch{continue}
     $role=$o.message.role; if($role -ne 'user' -and $role -ne 'assistant'){continue}
     $t=MsgText $o; if(-not $t){continue}
     Write-Host "`n[$role]" -ForegroundColor $(if($role -eq 'user'){'Green'}else{'Cyan'})
     Write-Host $t
   }
 }
 'resume'{
   if(-not $Id){ throw "セッション番号またはIDを指定してください。" }
   $f=Find-File $Id; if(-not $f){ throw "見つかりません: $Id" }
   $sid=$f.BaseName; $here=(Get-Location).Path
   $destDir=Join-Path $projects ($here -replace '[^A-Za-z0-9]','-')
   New-Item -ItemType Directory -Force -Path $destDir | Out-Null
   $dest=Join-Path $destDir "$sid.jsonl"
   if($f.FullName -ne $dest){ Copy-Item $f.FullName $dest -Force; Write-Host "現在のフォルダ向けに取り込みました。" -ForegroundColor Green }
   Write-Host "再開:" -ForegroundColor Cyan; Write-Host "  claude --resume $sid"
 }
 'path'{ if(-not $Id){ throw "番号/IDを指定してください。" }; $f=Find-File $Id; if($f){ $f.FullName } else { throw "見つかりません: $Id" } }
}
