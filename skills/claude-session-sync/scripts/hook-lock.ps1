<#  claude-session-sync : SessionStart/SessionEnd 用ロックフック (Windows)
    引数: acquire | release
    Claude Code がフック入力(JSON: cwd, session_id)を stdin で渡す。
    競合(別セッション/別デバイス)時は警告を出すが、既存ロックは上書きしない。  #>
param([ValidateSet('acquire','release')][string]$Action)
$ErrorActionPreference = 'SilentlyContinue'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ exit 0 }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$share = $cfg.share; if(-not $share){ exit 0 }
$scope = if($cfg.lockScope){ $cfg.lockScope } else { 'project' }

# stdin を UTF-8 で読む(WinPS 5.1 の OEM/ANSI 既定だと cwd の日本語が化けて key が不一致になる)
$cwd = (Get-Location).Path; $sid = ''
try {
  $reader = New-Object System.IO.StreamReader([System.Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
  $raw = $reader.ReadToEnd(); $reader.Dispose()
  if($raw){ $j = $raw | ConvertFrom-Json; if($j.cwd){ $cwd = $j.cwd }; if($j.session_id){ $sid = $j.session_id } }
} catch {}

$lockDir = Join-Path $share 'locks'; New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
$key  = if($scope -eq 'global'){ 'ACTIVE' } else { ($cwd -replace '[^A-Za-z0-9]','-') }
$lock = Join-Path $lockDir "$key.lock"
function LockSid($f){ if(Test-Path $f){ $m = Get-Content $f -Raw; if($m -match 'session=([^\s]+)'){ return $matches[1] } }; return '' }

if($Action -eq 'release'){
  if((Test-Path $lock) -and ((LockSid $lock) -eq $sid)){ Remove-Item $lock -Force }
  exit 0
}
# acquire
if(Test-Path $lock){
  $owner = LockSid $lock
  if($owner -and $owner -ne $sid){
    Write-Output "[claude-session-sync] WARNING: このプロジェクトは別セッション/別デバイスで使用中の可能性があります -> $((Get-Content $lock -Raw).Trim()) ／ 同時編集は履歴破損(.sync-conflict)の恐れ。もう一方を終了してから作業してください。"
    exit 0   # 競合時は上書きしない
  }
}
Set-Content $lock "machine=$env:COMPUTERNAME user=$env:USERNAME session=$sid scope=$scope key=$key start=$(Get-Date -Format s)" -Encoding utf8
exit 0
