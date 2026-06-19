<#  claude-session-sync : SessionStart/SessionEnd 用ロックフック (Windows)
    引数: acquire | release
    Claude Code がフック入力(JSON: cwd, session_id)を stdin で渡す。
    競合(別セッション/別デバイス)時は警告を出すが、既存ロックは上書きしない。  #>
param([ValidateSet('acquire','release')][string]$Action)
$ErrorActionPreference = 'SilentlyContinue'
if($env:CSS_TITLEGEN){ exit 0 }   # 自動タイトル生成中の claude -p はロック対象外
# フック出力は Claude が UTF-8 で読む。WinPS5.1 の既定出力(CP932)だと日本語が化けるので UTF-8 バイト列を直接書く。
function CssEmit([string]$s){
  try{ $b=[System.Text.Encoding]::UTF8.GetBytes($s+"`n"); $o=[System.Console]::OpenStandardOutput(); $o.Write($b,0,$b.Length); $o.Flush() }
  catch{ Write-Output $s }
}
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
    CssEmit "[claude-session-sync] WARNING: このプロジェクトは別セッション/別デバイスで使用中の可能性があります -> $((Get-Content $lock -Raw).Trim()) ／ 同時編集は履歴破損(.sync-conflict)の恐れ。もう一方を終了してから作業してください。"
    exit 0   # 競合時は上書きしない
  }
}
Set-Content $lock "machine=$env:COMPUTERNAME user=$env:USERNAME session=$sid scope=$scope key=$key start=$(Get-Date -Format s)" -Encoding utf8
# デバイスタグ(同機種識別用): sessionId -> deviceName を devices.map に一度だけ記録
if($sid){
  $dev = if($cfg.deviceName){ $cfg.deviceName } else { $env:COMPUTERNAME }
  $dm = Join-Path $share 'sessions\devices.map'
  $already = (Test-Path $dm) -and ((Get-Content $dm -Encoding utf8 -EA SilentlyContinue) -match "^$([regex]::Escape($sid))`t")
  if(-not $already){ Add-Content -Path $dm -Value "$sid`t$dev" -Encoding utf8 }
}
exit 0
