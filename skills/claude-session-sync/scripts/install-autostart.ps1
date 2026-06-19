<#  claude-session-sync : 自動起動 / リモート起動の設定 (Windows)
    - PC ログオン時に claude を自動起動(新規 / 最近 / 特定会話, リモート可)
    - スマホ等からのトリガで `claude --remote-control` を起動する常駐ウォッチャ
    いずれも管理者権限不要(Startup フォルダの shortcut で実現)。次回ログオンから有効。

    使い方:
      install-autostart.ps1 -Launch new            # ログオン時に新規会話で起動
      install-autostart.ps1 -Launch last -Remote   # 最近の会話を再開 + リモートON
      install-autostart.ps1 -Session <sid>         # 特定の会話を毎回再開
      install-autostart.ps1 -RemoteMode ask        # 起動時にリモートON/OFFを尋ねる
      install-autostart.ps1 -Watch                 # スマホからのトリガ起動を有効化
      install-autostart.ps1 -Status
      install-autostart.ps1 -Uninstall             # 全て解除  #>
[CmdletBinding()]
param(
  [ValidateSet('off','new','last')][string]$Launch,
  [string]$Session,
  [switch]$Remote, [switch]$NoRemote,
  [ValidateSet('true','false','ask')][string]$RemoteMode,
  [switch]$CheckMulti, [switch]$NoCheckMulti,
  [switch]$Watch, [switch]$NoWatch,
  [string]$WatchDir,
  [switch]$Uninstall,
  [switch]$Status
)
$ErrorActionPreference = 'Stop'
if($PSVersionTable.PSVersion.Major -lt 7 -and (Get-Command pwsh -EA SilentlyContinue)){ & pwsh -NoProfile -File $PSCommandPath @PSBoundParameters; exit $LASTEXITCODE }
$claude    = Join-Path $env:USERPROFILE '.claude'
$cfgPath   = Join-Path $claude 'session-sync.local.conf'
$scriptDir = $PSScriptRoot
$psExe = (Get-Command pwsh -EA SilentlyContinue).Source; if(-not $psExe){ $psExe = (Get-Command powershell).Source }
$startup  = [Environment]::GetFolderPath('Startup')
$bootLnk  = Join-Path $startup 'ClaudeSessionSync-Boot.lnk'
$watchLnk = Join-Path $startup 'ClaudeSessionSync-Watch.lnk'

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Config($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Make-Shortcut($path,$arguments,[bool]$hidden){ $ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut($path); $s.TargetPath=$psExe; $s.Arguments=$arguments; $s.WorkingDirectory=$env:USERPROFILE; $s.WindowStyle= if($hidden){7}else{1}; $s.Description='claude-session-sync'; $s.Save() }

if(-not (Test-Path $cfgPath)){ throw "未設定です。先に setup.ps1 を実行してください。" }
$cfg = Read-Config

if($Status){
  $wd = if($cfg.remoteWatchDir){ $cfg.remoteWatchDir } elseif($cfg.share){ Join-Path $cfg.share 'remote' } else { '(share未設定)' }
  Write-Host '=== 自動起動 / リモート起動 状態 (Windows) ===' -ForegroundColor Cyan
  Write-Host ("bootLaunch={0}  bootRemote={1}  bootCheckMulti={2}" -f $cfg.bootLaunch,$cfg.bootRemote,$cfg.bootCheckMulti)
  Write-Host ("remoteWatch={0}  watchDir={1}" -f $cfg.remoteWatch,$wd)
  Write-Host ("Startup ランチャ shortcut : 存在={0}  ({1})" -f (Test-Path $bootLnk),$bootLnk)
  Write-Host ("Startup ウォッチャ shortcut: 存在={0}  ({1})" -f (Test-Path $watchLnk),$watchLnk)
  return
}

if($Uninstall){
  Remove-Item $bootLnk,$watchLnk -Force -EA SilentlyContinue
  $cfg.bootLaunch='off'; $cfg.remoteWatch='false'
  Write-Config $cfg
  Write-Host '✔ 自動起動 / リモート起動ウォッチャを解除しました(設定 off)。' -ForegroundColor Green
  return
}

# --- bootLaunch ---
if($Session){ $cfg.bootLaunch = $Session }
elseif($Launch){ $cfg.bootLaunch = $Launch }
elseif(-not $cfg.Contains('bootLaunch')){ $cfg.bootLaunch = 'off' }

# --- bootRemote ---
if($RemoteMode){ $cfg.bootRemote = $RemoteMode }
elseif($Remote){ $cfg.bootRemote = 'true' }
elseif($NoRemote){ $cfg.bootRemote = 'false' }
elseif(-not $cfg.Contains('bootRemote')){ $cfg.bootRemote = 'false' }

# --- bootCheckMulti ---
if($CheckMulti){ $cfg.bootCheckMulti = 'true' }
elseif($NoCheckMulti){ $cfg.bootCheckMulti = 'false' }
elseif(-not $cfg.Contains('bootCheckMulti')){ $cfg.bootCheckMulti = 'true' }

# --- remoteWatch ---
if($Watch){ $cfg.remoteWatch = 'true' }
elseif($NoWatch){ $cfg.remoteWatch = 'false' }
elseif(-not $cfg.Contains('remoteWatch')){ $cfg.remoteWatch = 'false' }
if($WatchDir){ $cfg.remoteWatchDir = $WatchDir }

Write-Config $cfg

# --- Startup shortcuts(管理者不要) ---
if($cfg.bootLaunch -and $cfg.bootLaunch -ne 'off'){
  Make-Shortcut $bootLnk ("-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\boot-launch.ps1`"") $false
  Write-Host ("✔ ログオン自動起動を登録: bootLaunch={0} remote={1} checkMulti={2}" -f $cfg.bootLaunch,$cfg.bootRemote,$cfg.bootCheckMulti) -ForegroundColor Green
} else {
  Remove-Item $bootLnk -Force -EA SilentlyContinue
  Write-Host '• 自動起動は off(ランチャ shortcut なし)' -ForegroundColor DarkGray
}

if($cfg.remoteWatch -eq 'true'){
  Make-Shortcut $watchLnk ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\remote-watch.ps1`"") $true
  $wd = if($cfg.remoteWatchDir){ $cfg.remoteWatchDir } else { Join-Path $cfg.share 'remote' }
  New-Item -ItemType Directory -Force -Path (Join-Path $wd 'inbox') | Out-Null
  Write-Host ("✔ リモート起動ウォッチャを登録: 監視={0}\inbox" -f $wd) -ForegroundColor Green
  Write-Host '  → スマホから同期フォルダの inbox に1ファイル置くと claude --remote-control が起動します。' -ForegroundColor DarkGray
  Write-Host '     新規=任意名 (例 wake.trig) / 特定会話=ファイル名か中身に session-id を含める。' -ForegroundColor DarkGray
} else {
  Remove-Item $watchLnk -Force -EA SilentlyContinue
}

Write-Host '完了。変更は次回ログオンから有効です(今すぐ試すには boot-launch.ps1 を直接実行)。' -ForegroundColor Cyan
