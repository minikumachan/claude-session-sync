<#  claude-session-sync : ロック付きで Claude を起動 (Windows)  #>
[CmdletBinding()]
param([switch]$Force, [switch]$Unlock, [Parameter(ValueFromRemainingArguments=$true)] $ClaudeArgs)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ throw "未設定です。先に setup.ps1 -Share '<...\_ClaudeCode>' を実行してください。" }

$cfg = @{}; foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = $matches[2] } }
$share = $cfg.share; if(-not $share){ throw "config に share がありません。" }
$scope = if($cfg.lockScope){ $cfg.lockScope } else { 'project' }
$lockDir = Join-Path $share 'locks'; New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }
$key  = if($scope -eq 'global'){ 'ACTIVE' } else { Encode((Get-Location).Path) }
$lock = Join-Path $lockDir "$key.lock"

if($Unlock){ if(Test-Path $lock){ Remove-Item $lock -Force; Write-Host "🔓 解除: $key" -ForegroundColor Green } else { Write-Host "ロックなし: $key" }; return }

if(Test-Path $lock){
  $info = (Get-Content $lock -Raw).Trim()
  if(-not $Force){
    Write-Host "⛔ このプロジェクト/セッションは使用中の可能性: $info" -ForegroundColor Red
    Write-Host "   解決: もう一方で終了する / 残骸なら -Force / 強制解除は cc.ps1 -Unlock" -ForegroundColor Yellow
    return
  }
  Write-Host "⚠ -Force: 既存ロックを上書き → $info" -ForegroundColor Yellow
}
$me = "machine=$env:COMPUTERNAME user=$env:USERNAME pid=$PID scope=$scope key=$key start=$(Get-Date -Format s)"
Set-Content $lock $me -Encoding utf8
Write-Host "🔒 lock: $key" -ForegroundColor Green
try { claude @ClaudeArgs }
finally {
  if((Test-Path $lock) -and ((Get-Content $lock -Raw) -match "pid=$PID(\D|$)")){ Remove-Item $lock -Force; Write-Host "🔓 unlock: $key" -ForegroundColor Green }
}
