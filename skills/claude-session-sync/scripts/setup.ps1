<#  claude-session-sync : setup / link / status  (Windows / PowerShell 5+)  #>
[CmdletBinding()]
param(
  [string]$Share,
  [switch]$WithSkills,
  [ValidateSet('project','global')][string]$LockScope = 'project',
  [ValidateSet('prepare','link','all')][string]$Phase = 'all',
  [switch]$Status,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'

function Read-Config {
  $h = [ordered]@{}
  if(Test-Path $cfgPath){ foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]] = $matches[2] } } }
  $h
}
function Write-Config($h){ ($h.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`r`n" | Set-Content $cfgPath -Encoding utf8 }

if($Status){
  $c = Read-Config
  Write-Host "=== session-sync 状態 (Windows) ===" -ForegroundColor Cyan
  Write-Host "config: $cfgPath  存在=$(Test-Path $cfgPath)"
  $c.GetEnumerator() | ForEach-Object { "  $($_.Key) = $($_.Value)" }
  foreach($name in 'projects','skills'){
    $it = Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue
    if($it){ Write-Host ("  ~/.claude/{0}: LinkType={1} Target={2}" -f $name, $it.LinkType, $it.Target) }
  }
  if($c.share){ Get-ChildItem (Join-Path $c.share 'locks') -Filter *.lock -EA SilentlyContinue | ForEach-Object { Write-Host "  lock $($_.Name): $((Get-Content $_.FullName -Raw).Trim())" } }
  return
}

$cfg = Read-Config
if(-not $Share){ $Share = $cfg.share }
if(-not $Share){ throw "共有フォルダを指定してください:  setup.ps1 -Share '<...\_ClaudeCode>'" }
$Share = $Share.TrimEnd('\')

$wantSkills = [bool]($WithSkills -or $cfg.linkSkills -eq 'true')
$dirs = @("$Share\sessions\projects","$Share\locks","$Share\exports")
if($wantSkills){ $dirs += "$Share\skills" }
New-Item -ItemType Directory -Force -Path $dirs | Out-Null

$cfg.share = $Share; $cfg.linkProjects = 'true'
$cfg.linkSkills = $(if($wantSkills){'true'}else{'false'}); $cfg.lockScope = $LockScope
Write-Config $cfg
Write-Host "✔ config 保存: $cfgPath" -ForegroundColor Green

$targets = [ordered]@{ projects = "$Share\sessions\projects" }
if($wantSkills){ $targets.skills = "$Share\skills" }

if($Phase -in 'prepare','all'){
  foreach($name in $targets.Keys){
    $local = Join-Path $claude $name; $tgt = $targets[$name]
    $it = Get-Item $local -Force -EA SilentlyContinue
    if($it -and -not $it.LinkType){
      $stamp = Get-Date -Format yyyyMMdd_HHmmss
      robocopy $local "$claude\${name}_backup_$stamp" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
      Write-Host "✔ バックアップ: ${name}_backup_$stamp" -ForegroundColor Green
      robocopy $local $tgt /E /XN /XO /XC /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null   # local -> share (新規のみ)
      robocopy $tgt $local /E /XN /XO /XC /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null   # share -> local (新規のみ)
      Write-Host "✔ $name を非破壊マージ" -ForegroundColor Green
    }
  }
}

if($Phase -in 'link','all'){
  foreach($name in $targets.Keys){
    $local = Join-Path $claude $name; $tgt = $targets[$name]
    $it = Get-Item $local -Force -EA SilentlyContinue
    if($it -and $it.LinkType){ Write-Host "• $name は既にリンク済み ($($it.Target))" -ForegroundColor DarkGray; continue }
    if($it){
      try { Rename-Item $local "${name}_local_old" -ErrorAction Stop }
      catch {
        Write-Host "⛔ $name をリネームできません。Claude を全終了してから  setup.ps1 -Phase link  を再実行してください。" -ForegroundColor Red
        continue
      }
    }
    cmd /c mklink /J "$local" "$tgt" | Out-Null
    $chk = Get-Item $local -Force -EA SilentlyContinue
    if($chk -and $chk.LinkType){ Write-Host "✔ $name → $($chk.Target)" -ForegroundColor Green }
    else { Write-Host "⛔ $name のリンク作成に失敗しました。" -ForegroundColor Red }
  }
}
Write-Host "`n完了。起動は cc.ps1、別デバイス会話の取り込みは resume-other.ps1。" -ForegroundColor Cyan
