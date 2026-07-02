<#  claude-session-sync : ロック付きで Claude を起動 (Windows)
    transport=folder … 共有フォルダ内のロックファイルで排他(原子的作成)
    transport=git    … 起動時に git pull + リモートロック取得、終了時に push + ロック解除  #>
[CmdletBinding()]
param([switch]$Force, [switch]$Unlock, [Parameter(ValueFromRemainingArguments=$true)] $ClaudeArgs)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ throw "未設定です。先に setup.ps1 を実行してください。" }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$scope = if($cfg.lockScope){ $cfg.lockScope } else { 'project' }
$transport = if($cfg.transport){ $cfg.transport } else { 'folder' }
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }
$key = if($scope -eq 'global'){ 'ACTIVE' } else { Encode((Get-Location).Path) }

# 実体の claude(ラッパー関数を避ける)。Unlock 時は不要なので後段で解決。
function Resolve-Claude { (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source }

# ===== git transport =====
if($transport -eq 'git'){
  $sync = Join-Path $PSScriptRoot 'sync.ps1'
  $psExe = if($PSVersionTable.PSVersion.Major -ge 6){ 'pwsh' } else { 'powershell' }
  if($Unlock){ & $sync unlock -Key $key; return }
  if(-not (Get-Command git -EA SilentlyContinue)){ throw "git が見つかりません(git transport に必要)。git を導入してください。" }
  $realClaude = Resolve-Claude
  if(-not $realClaude){ throw "claude コマンドが見つかりません。Claude Code を導入し PATH を確認してください。" }
  & $sync pull
  & $psExe -NoProfile -ExecutionPolicy Bypass -File $sync lock -Key $key
  $rc = $LASTEXITCODE
  if($rc -eq 2){
    if(-not $Force){ Write-Host "   解決: もう一方で終了 / 残骸なら cc.ps1 -Unlock(または sync.ps1 unlock -Key $key)で解除。" -ForegroundColor Yellow; return }
    Write-Host "⚠ -Force: 既存リモートロックを解除して取得し直します。" -ForegroundColor Yellow
    & $sync unlock -Key $key
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $sync lock -Key $key
    if($LASTEXITCODE -eq 2){ Write-Host "⛔ それでも取得できません。中止。" -ForegroundColor Red; return }
  }
  try { & $realClaude @ClaudeArgs }
  finally {
    & $sync push -Message "session end $env:COMPUTERNAME $(Get-Date -Format s)"
    & $sync unlock -Key $key
  }
  return
}

# ===== folder transport (file lock) =====
$share = $cfg.share; if(-not $share){ throw "config に share がありません。setup.ps1 を実行してください。" }
$lockDir = Join-Path $share 'locks'; New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
$lock = Join-Path $lockDir "$key.lock"
if($Unlock){ if(Test-Path $lock){ Remove-Item $lock -Force; Write-Host "🔓 解除: $key" -ForegroundColor Green } else { Write-Host "ロックなし: $key" }; return }

$realClaude = Resolve-Claude
if(-not $realClaude){ throw "claude コマンドが見つかりません。Claude Code を導入し PATH を確認してください。" }

# 原子的にロックを作成(CreateNew: 既存なら例外)。TOCTOU 競合を回避。
$me = "machine=$env:COMPUTERNAME user=$env:USERNAME pid=$PID scope=$scope key=$key start=$(Get-Date -Format s)"
function New-LockFile($path,$text){
  $fs = [System.IO.File]::Open($path,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
  try { $b=[System.Text.Encoding]::UTF8.GetBytes($text); $fs.Write($b,0,$b.Length) } finally { $fs.Dispose() }
}
try { New-LockFile $lock $me }
catch {
  $info = try { ((Get-Content $lock -Raw -EA SilentlyContinue) -replace '[\x00-\x1F\x7F]','').Trim() } catch { '' }   # 共有ロックの ESC/制御文字を除去
  if(-not $Force){
    Write-Host "⛔ このプロジェクト/セッションは使用中の可能性: $info" -ForegroundColor Red
    Write-Host "   解決: もう一方で終了する / 残骸なら -Force / 強制解除は cc.ps1 -Unlock" -ForegroundColor Yellow
    return
  }
  Write-Host "⚠ -Force: 既存ロックを上書き → $info" -ForegroundColor Yellow
  Remove-Item $lock -Force -EA SilentlyContinue
  New-LockFile $lock $me
}
Write-Host "🔒 lock: $key" -ForegroundColor Green
try { & $realClaude @ClaudeArgs }
finally {
  if((Test-Path $lock) -and ((Get-Content $lock -Raw -EA SilentlyContinue) -match "pid=$PID(\D|$)")){ Remove-Item $lock -Force; Write-Host "🔓 unlock: $key" -ForegroundColor Green }
}
