<#  claude-session-sync : 自動起動 / リモート起動の設定 (Windows)
    起動項目(複数可)は ~/.claude/session-sync.boot.json(配列・非同期)に保存。
    共通設定(bootCheckMulti / remoteWatch / remoteWatchDir)は session-sync.local.conf。
    管理者権限不要(Startup フォルダの shortcut)。次回ログオンから有効。
    通常は対話メニュー `claude -a`(autostart-ui.ps1)から呼ばれる。フラグ直接指定も可:
      install-autostart.ps1 -Launch new [-Model sonnet] [-Effort medium] [-Remote|-NoRemote|-RemoteMode ask]
      install-autostart.ps1 -Launch last        # 最近の会話を再開(モデル/深度は会話のものを使用)
      install-autostart.ps1 -Session <sid>      # 特定の会話を再開(同上)
      install-autostart.ps1 -Watch              # スマホからのトリガ起動を有効化
      install-autostart.ps1 -Apply              # 設定変更せず shortcut を現状に合わせて再登録
      install-autostart.ps1 -Status / -Uninstall  #>
[CmdletBinding()]
param(
  [ValidateSet('off','new','last')][string]$Launch,
  [string]$Session,
  [string]$Model,
  [ValidateSet('low','medium','high','xhigh','max','')][string]$Effort,
  [switch]$Remote, [switch]$NoRemote,
  [ValidateSet('true','false','ask')][string]$RemoteMode,
  [switch]$CheckMulti, [switch]$NoCheckMulti,
  [switch]$Watch, [switch]$NoWatch,
  [string]$WatchDir,
  [switch]$Apply, [switch]$Uninstall, [switch]$Status
)
$ErrorActionPreference = 'Stop'
if($PSVersionTable.PSVersion.Major -lt 7 -and (Get-Command pwsh -EA SilentlyContinue)){ & pwsh -NoProfile -File $PSCommandPath @PSBoundParameters; exit $LASTEXITCODE }
$claude    = Join-Path $env:USERPROFILE '.claude'
$cfgPath   = Join-Path $claude 'session-sync.local.conf'
$bootJson  = Join-Path $claude 'session-sync.boot.json'
$scriptDir = $PSScriptRoot
$psExe = (Get-Command pwsh -EA SilentlyContinue).Source; if(-not $psExe){ $psExe = (Get-Command powershell).Source }
$startup  = [Environment]::GetFolderPath('Startup')
$bootLnk  = Join-Path $startup 'ClaudeSessionSync-Boot.lnk'
$watchLnk = Join-Path $startup 'ClaudeSessionSync-Watch.lnk'

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Config($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Read-Entries { if(Test-Path $bootJson){ try{ $a=Get-Content $bootJson -Raw -Encoding utf8 | ConvertFrom-Json; if($a){ return @($a) } }catch{} }; @() }
function Write-Entries($arr){ $json=ConvertTo-Json @($arr) -Depth 6; [System.IO.File]::WriteAllText($bootJson,$json,(New-Object System.Text.UTF8Encoding($false))) }
function Make-Shortcut($path,$arguments,[bool]$hidden){ $ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut($path); $s.TargetPath=$psExe; $s.Arguments=$arguments; $s.WorkingDirectory=$env:USERPROFILE; $s.WindowStyle= if($hidden){7}else{1}; $s.Description='claude-session-sync'; $s.Save() }
function EntryLabel($e){
  switch("$($e.type)"){
    'new'    { "新規(壁打ち) model=$(if($e.model){$e.model}else{'(既定)'}) effort=$(if($e.effort){$e.effort}else{'(既定)'})" }
    'last'   { "最近の会話を再開 (会話のモデル/深度を使用)" }
    'resume' { "特定の会話 sid=$($e.sid) (会話のモデル/深度を使用)" }
    default  { "$($e.type)" }
  }
}
function Register-Shortcuts {
  $cfg = Read-Config
  if((Read-Entries).Count -gt 0){
    Make-Shortcut $bootLnk ("-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\boot-launch.ps1`"") $false
  } else { Remove-Item $bootLnk -Force -EA SilentlyContinue }
  if($cfg.remoteWatch -eq 'true'){
    Make-Shortcut $watchLnk ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\remote-watch.ps1`"") $true
    $wd = if($cfg.remoteWatchDir){ $cfg.remoteWatchDir } else { Join-Path $cfg.share 'remote' }
    if($wd){ New-Item -ItemType Directory -Force -Path (Join-Path $wd 'inbox') | Out-Null }
  } else { Remove-Item $watchLnk -Force -EA SilentlyContinue }
}

if(-not (Test-Path $cfgPath)){ throw "未設定です。先に setup.ps1 を実行してください。" }
$cfg = Read-Config

if($Status){
  $wd = if($cfg.remoteWatchDir){ $cfg.remoteWatchDir } elseif($cfg.share){ Join-Path $cfg.share 'remote' } else { '(share未設定)' }
  Write-Host '=== 自動起動 / リモート起動 状態 (Windows) ===' -ForegroundColor Cyan
  $entries = Read-Entries
  if($entries.Count -gt 0){ Write-Host '自動起動する会話:'; for($i=0;$i -lt $entries.Count;$i++){ Write-Host ("  {0}) {1}  リモート={2}" -f ($i+1),(EntryLabel $entries[$i]),$entries[$i].remote) } }
  else { Write-Host '自動起動する会話: なし' }
  Write-Host ("共通: 多重起動チェック={0}  スマホからの起動(remoteWatch)={1}  watchDir={2}" -f $cfg.bootCheckMulti,$cfg.remoteWatch,$wd)
  Write-Host ("Startup ランチャ shortcut : 存在={0}" -f (Test-Path $bootLnk))
  Write-Host ("Startup ウォッチャ shortcut: 存在={0}" -f (Test-Path $watchLnk))
  return
}

if($Uninstall){
  Remove-Item $bootLnk,$watchLnk -Force -EA SilentlyContinue
  Remove-Item $bootJson -Force -EA SilentlyContinue
  $cfg.bootLaunch='off'; $cfg.remoteWatch='false'; Write-Config $cfg
  Write-Host '✔ 自動起動 / リモート起動ウォッチャを解除しました(項目削除・設定 off)。' -ForegroundColor Green
  return
}

if($Apply){
  Register-Shortcuts
  Write-Host '✔ shortcut を現在の設定に合わせて再登録しました。' -ForegroundColor Green
  return
}

# --- 単一項目をフラグから書く(boot.json を置き換え) ---
if($PSBoundParameters.ContainsKey('Launch') -or $Session){
  if($Launch -eq 'off'){ Write-Entries @() }
  else {
    $e = [ordered]@{}
    if($Session){ $e.type='resume'; $e.sid=$Session }
    elseif($Launch -eq 'last'){ $e.type='last' }
    else { $e.type='new'; $e.model= if($Model){$Model}else{'sonnet'}; $e.effort= if($PSBoundParameters.ContainsKey('Effort')){$Effort}else{'medium'} }
    $remStr = if($RemoteMode){ $RemoteMode } elseif($Remote){ 'true' } elseif($NoRemote){ 'false' } else { 'ask' }
    $e.remote = switch($remStr){ 'true'{$true} 'false'{$false} default{'ask'} }
    Write-Entries @([pscustomobject]$e)
  }
}

# --- 共通設定 ---
if($CheckMulti){ $cfg.bootCheckMulti='true' } elseif($NoCheckMulti){ $cfg.bootCheckMulti='false' } elseif(-not $cfg.Contains('bootCheckMulti')){ $cfg.bootCheckMulti='true' }
if($Watch){ $cfg.remoteWatch='true' } elseif($NoWatch){ $cfg.remoteWatch='false' } elseif(-not $cfg.Contains('remoteWatch')){ $cfg.remoteWatch='false' }
if($WatchDir){ $cfg.remoteWatchDir=$WatchDir }
Write-Config $cfg

Register-Shortcuts

$entries = Read-Entries
Write-Host ("✔ 保存しました。自動起動項目={0}件  多重起動チェック={1}  スマホからの起動={2}" -f $entries.Count,$cfg.bootCheckMulti,$cfg.remoteWatch) -ForegroundColor Green
if($entries.Count -gt 0){ for($i=0;$i -lt $entries.Count;$i++){ Write-Host ("   {0}) {1}  リモート={2}" -f ($i+1),(EntryLabel $entries[$i]),$entries[$i].remote) -ForegroundColor DarkGray } }
if($cfg.remoteWatch -eq 'true'){ $wd= if($cfg.remoteWatchDir){$cfg.remoteWatchDir}else{(Join-Path $cfg.share 'remote')}; Write-Host "  → スマホから $wd\inbox に1ファイル置くと claude --remote-control が起動します。" -ForegroundColor DarkGray }
Write-Host '完了。変更は次回ログオンから有効です。' -ForegroundColor Cyan
