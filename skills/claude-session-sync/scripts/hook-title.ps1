<#  claude-session-sync : Stop フック = 会話タイトルの自動更新 (Windows)
    Claude が応答を終えるたびに呼ばれる。一定ターンごとに title-gen.ps1 を
    バックグラウンドで起動し、会話内容に合った分かりやすいタイトルへ改名する。
    フック自体は即座に終了する(生成は非同期)。  #>
$ErrorActionPreference='SilentlyContinue'
if($env:CSS_TITLEGEN){ exit 0 }   # title-gen 経由の claude -p からの再入を無視

$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ exit 0 }
$cfg=@{}; foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]]=($matches[2].TrimEnd("`r")) } }
$autoTitle = if($cfg.ContainsKey('autoTitle')){ $cfg.autoTitle -ne 'false' } else { $true }
if(-not $autoTitle){ exit 0 }
$every = 5; if($cfg.titleEvery -and [int]::TryParse($cfg.titleEvery,[ref]$null)){ $every=[int]$cfg.titleEvery }; if($every -lt 1){ $every=1 }

# --- フック入力(JSON) を UTF-8 で読む ---
$sid=''; $tp=''
try {
  $reader=New-Object System.IO.StreamReader([System.Console]::OpenStandardInput(),(New-Object System.Text.UTF8Encoding($false)))
  $raw=$reader.ReadToEnd(); $reader.Dispose()
  if($raw){ $j=$raw|ConvertFrom-Json; if($j.session_id){ $sid=[string]$j.session_id }; if($j.transcript_path){ $tp=[string]$j.transcript_path } }
} catch {}
if(-not $sid -or -not $tp -or -not (Test-Path $tp)){ exit 0 }
if($sid -notmatch '^[0-9A-Fa-f][0-9A-Fa-f-]{7,63}$'){ exit 0 }   # セキュリティ: sid を .cnt パスに使う。UUID形以外は拒否(パストラバーサル防止)

# --- ユーザー発話数を概算(上限つき) ---
$userMsgs=0; $n=0
foreach($line in [System.IO.File]::ReadLines($tp)){ if($n -ge 800){ break }; $n++; if($line.Contains('"type":"user"')){ $userMsgs++ } }
if($userMsgs -lt 2){ exit 0 }   # 内容が乏しいうちは付けない

# --- スロットリング: 前回生成時のユーザー発話数と比較 ---
$stateDir=Join-Path $claude '.session-sync\title-state'; New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile=Join-Path $stateDir "$sid.cnt"
$last=0; if(Test-Path $stateFile){ $v=Get-Content $stateFile -Raw -EA SilentlyContinue; [void][int]::TryParse(($v -replace '\D',''),[ref]$last) }
if(-not ($last -eq 0 -or ($userMsgs - $last) -ge $every)){ exit 0 }
Set-Content $stateFile "$userMsgs" -Encoding ascii   # 二重起動防止のため先に記録

# --- title-gen を非同期起動 ---
$psexe=(Get-Command pwsh -EA SilentlyContinue).Source; if(-not $psexe){ $psexe='powershell' }
try {
  Start-Process -FilePath $psexe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
    (Join-Path $PSScriptRoot 'title-gen.ps1'),'-Sid',$sid,'-Transcript',$tp
  ) | Out-Null
} catch {}
exit 0
