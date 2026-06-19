<#  claude-session-sync : PC ログオン時の自動起動ランチャー (Windows)
    config(session-sync.local.conf):
      bootLaunch     = off | new | last | <session-id>   起動する会話(既定 off)
      bootRemote     = true | false | ask                Remote Control(スマホ操作)を付けるか
      bootCheckMulti = true | false                      起動前に他デバイス使用中チェック(既定 true)
    Startup フォルダの shortcut から呼ばれる。install-autostart.ps1 で登録/解除。  #>
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'SilentlyContinue'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ Write-Host 'session-sync 未設定です。先に setup を実行してください。'; Start-Sleep 4; return }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }

$bootLaunch = if($cfg.bootLaunch){ $cfg.bootLaunch } else { 'off' }
if($bootLaunch -eq 'off'){ return }
$bootRemote = if($cfg.bootRemote){ $cfg.bootRemote } else { 'false' }
$checkMulti = if($cfg.ContainsKey('bootCheckMulti')){ $cfg.bootCheckMulti -ne 'false' } else { $true }

function Resolve-Claude { (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source }
$rc = Resolve-Claude
if(-not $rc){ Write-Host '⛔ claude コマンドが見つかりません。Claude Code を導入し PATH を確認してください。'; Start-Sleep 6; return }

# --- 多重起動チェック(他デバイスが共有ロックを保持していないか) ---
function Active-OtherLocks {
  $share = $cfg.share; if(-not $share){ return @() }
  $ld = Join-Path $share 'locks'; if(-not (Test-Path $ld)){ return @() }
  $now = Get-Date; $out = @()
  foreach($lf in (Get-ChildItem $ld -Filter *.lock -File -EA SilentlyContinue)){
    if(($now - $lf.LastWriteTime).TotalHours -gt 12){ continue }   # 12h 超は残骸とみなして無視
    $c = (Get-Content $lf.FullName -Raw -EA SilentlyContinue)
    if($c -match 'machine=([^\s]+)'){ if($matches[1] -and $matches[1] -ne $env:COMPUTERNAME){ $out += $c.Trim() } }
  }
  ,$out
}
if($checkMulti){
  $others = Active-OtherLocks
  if($others.Count -gt 0){
    Write-Host '⛔ 別デバイスで Claude が使用中の可能性があります(同時起動は履歴破損 .sync-conflict の恐れ):' -ForegroundColor Red
    $others | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
    Write-Host '自動起動を中止しました。もう一方を終了してから手動で起動してください。' -ForegroundColor Yellow
    Start-Sleep 8; return
  }
}

# --- どの会話で開くか ---
$cargs = @(); $resumeSid = $null; $startCwd = $null
$pjRoot = Join-Path $claude 'projects'
function Get-SessionCwd($file){ try{ $f = Get-Content $file.FullName -TotalCount 1 -Encoding utf8; if($f){ $o = $f | ConvertFrom-Json; if($o.cwd){ return $o.cwd } } } catch {}; return $null }
switch -Regex ($bootLaunch){
  '^new$'  { }
  '^last$' {
    $f = Get-ChildItem -Path $pjRoot -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($f){ $resumeSid = $f.BaseName; $startCwd = Get-SessionCwd $f }
  }
  default  {   # 特定セッションID
    $resumeSid = $bootLaunch
    $f = Get-ChildItem -Path $pjRoot -Recurse -Filter "$bootLaunch.jsonl" -File -EA SilentlyContinue | Select-Object -First 1
    if($f){ $startCwd = Get-SessionCwd $f }
  }
}
if($startCwd -and (Test-Path $startCwd)){ Set-Location $startCwd }
if($resumeSid){ $cargs += @('--resume',$resumeSid) }

# --- Remote Control(スマホ/claude.ai から操作) ---
$useRemote = $false
switch($bootRemote){
  'true' { $useRemote = $true }
  'ask'  {
    Write-Host 'リモート操作(スマホ/claude.ai から PC の Claude を操作)を有効にしますか? [y/N] (8秒で N)' -ForegroundColor Cyan
    try {
      $deadline = (Get-Date).AddSeconds(8); $key = $null
      while((Get-Date) -lt $deadline){ if($Host.UI.RawUI.KeyAvailable){ $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); break }; Start-Sleep -Milliseconds 150 }
      if($key -and ("$($key.Character)" -match '^[yY]$')){ $useRemote = $true }
    } catch { $useRemote = $false }   # 非対話ホストでは既定OFF
  }
  default { $useRemote = $false }
}
if($useRemote){ $cargs += '--remote-control' }

Write-Host ("▶ claude {0}" -f ($cargs -join ' ')) -ForegroundColor Green
if($DryRun){ Write-Host '(DryRun: 起動しません)'; return }
& $rc @cargs
