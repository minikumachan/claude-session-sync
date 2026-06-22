<#  claude-session-sync : シェル統合(`claude -h`=履歴UI / `claude -a`=自動起動設定)(Windows)
    どのシェル(PowerShell / cmd.exe / Git Bash・MSYS)からでも `claude -h` が履歴UIになるよう、
    2 系統で横取りする(どちらか片方でも動くので「全シェル・全状況」をカバー):
      (A) PowerShell プロファイルに `claude` 関数を追加(プロファイル読込時に最速で横取り)。
      (B) ~/.claude/css-bin に shim(claude.cmd / claude.ps1 / claude)を置き、User PATH の先頭へ追加。
          → cmd.exe・Git Bash・プロファイル未読込の pwsh でも `claude -h` を横取りできる。
    `-h`/`--history`=履歴UI、`-a`/`--autostart`=自動起動・リモート設定。`-r`(公式 --resume)等は実体の claude へ素通し。
    css-bin はデバイス毎ローカル(同期される ~/.claude/skills 配下には置かない)。実体 claude は PATH から css-bin を除いて解決。
      install-shell-wrap.ps1            # 導入
      install-shell-wrap.ps1 -Uninstall # 削除  #>
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
$claudeHome = Join-Path $env:USERPROFILE '.claude'
$binDir     = Join-Path $claudeHome 'css-bin'
$script:pathChanged = $false
$begin = '# >>> claude-session-sync >>>'
$end   = '# <<< claude-session-sync <<<'

# ===== (A) PowerShell プロファイルの claude 関数 =====
$block = @"
$begin
function claude {
  if (`$args.Count -ge 1 -and (`$args[0] -eq '-h' -or `$args[0] -eq '--history')) {
    & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\history-ui.ps1"
  } elseif (`$args.Count -ge 1 -and (`$args[0] -eq '-a' -or `$args[0] -eq '--autostart')) {
    & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\autostart-ui.ps1"
  } else {
    `$__cssbin = Join-Path `$env:USERPROFILE '.claude\css-bin'
    `$__rc = (Get-Command claude.cmd,claude.exe -CommandType Application -All -ErrorAction SilentlyContinue | Where-Object { (Split-Path `$_.Source -Parent) -ne `$__cssbin } | Select-Object -First 1).Source
    if (`$__rc) { & `$__rc @args } else { Write-Error 'real claude not found' }
  }
}
$end
"@

$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @("$docs\PowerShell\profile.ps1", "$docs\WindowsPowerShell\profile.ps1") | Select-Object -Unique
foreach($pf in $profiles){
  $dir = Split-Path $pf -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $content = if(Test-Path $pf){ Get-Content $pf -Raw } else { '' }
  if(-not $content){ $content='' }
  # 旧/新どちらのマーカー(# >>> claude-session-sync …)も除去(冪等・-r版からの移行対応)
  $content = [regex]::Replace($content, "(?s)# >>> claude-session-sync.*?# <<< claude-session-sync <<<\r?\n?", "")
  if(-not $Uninstall){ $content = $content.TrimEnd() + "`r`n`r`n" + $block + "`r`n" }
  Set-Content $pf $content.TrimEnd() -Encoding utf8
  Write-Host "$(if($Uninstall){'削除'}else{'導入'})(プロファイル): $pf" -ForegroundColor Green
}

# ===== (B) css-bin の shim(全シェル対応)=====
function Write-Shim($path,$text,[string]$eol){
  $t = $text -replace "`r`n","`n"        # まず LF に正規化
  if($eol -eq 'crlf'){ $t = $t -replace "`n","`r`n" }
  [System.IO.File]::WriteAllText($path,$t,(New-Object System.Text.UTF8Encoding($false)))  # BOM 無し(.cmd は BOM があると先頭行が壊れる)
}

# cmd.exe 用。-h/-a を pwsh(無ければ powershell)で起動。それ以外は PATH から css-bin を除いた実体 claude へ。
$cmdShim = @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "_a=%~1"
if /I "%_a%"=="-h"          goto :hist
if /I "%_a%"=="--history"   goto :hist
if /I "%_a%"=="-a"          goto :auto
if /I "%_a%"=="--autostart" goto :auto
goto :real
:hist
where pwsh >nul 2>nul
if errorlevel 1 ( powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-session-sync\scripts\history-ui.ps1" ) else ( pwsh -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-session-sync\scripts\history-ui.ps1" )
exit /b %ERRORLEVEL%
:auto
where pwsh >nul 2>nul
if errorlevel 1 ( powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-session-sync\scripts\autostart-ui.ps1" ) else ( pwsh -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-session-sync\scripts\autostart-ui.ps1" )
exit /b %ERRORLEVEL%
:real
set "_self=%~dp0"
set "_real="
for /f "delims=" %%I in ('where claude.cmd 2^>nul') do (
  set "_d=%%~dpI"
  if /I not "!_d!"=="%_self%" if not defined _real set "_real=%%I"
)
if not defined _real for /f "delims=" %%I in ('where claude.exe 2^>nul') do (
  set "_d=%%~dpI"
  if /I not "!_d!"=="%_self%" if not defined _real set "_real=%%I"
)
if not defined _real ( echo [claude-session-sync] real claude not found on PATH 1>&2 & exit /b 1 )
endlocal & "%_real%" %*
'@

# pwsh -NoProfile / プロファイル未読込の Windows PowerShell 用。
$ps1Shim = @'
#!/usr/bin/env pwsh
if ($args.Count -ge 1 -and ($args[0] -eq '-h' -or $args[0] -eq '--history')) {
  & "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\history-ui.ps1"
} elseif ($args.Count -ge 1 -and ($args[0] -eq '-a' -or $args[0] -eq '--autostart')) {
  & "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\autostart-ui.ps1"
} else {
  $__cssbin = Join-Path $env:USERPROFILE '.claude\css-bin'
  $__rc = (Get-Command claude.cmd,claude.exe -CommandType Application -All -ErrorAction SilentlyContinue | Where-Object { (Split-Path $_.Source -Parent) -ne $__cssbin } | Select-Object -First 1).Source
  if ($__rc) { & $__rc @args; exit $LASTEXITCODE } else { Write-Error 'real claude not found'; exit 1 }
}
'@

# Git Bash / MSYS 用。Windows の python には curses が無いので -h は PowerShell 版UIで起動する。
$shShim = @'
#!/bin/sh
# claude-session-sync shim (Windows / Git Bash・MSYS)
WIN_HOME="${USERPROFILE:-$HOME}"
PS="powershell"
command -v pwsh >/dev/null 2>&1 && PS="pwsh"
case "${1:-}" in
  -h|--history)   exec "$PS" -NoProfile -ExecutionPolicy Bypass -File "$WIN_HOME\\.claude\\skills\\claude-session-sync\\scripts\\history-ui.ps1" ;;
  -a|--autostart) exec "$PS" -NoProfile -ExecutionPolicy Bypass -File "$WIN_HOME\\.claude\\skills\\claude-session-sync\\scripts\\autostart-ui.ps1" ;;
esac
self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
real=""
oldifs="$IFS"; IFS=:
for d in $PATH; do
  [ "$d" = "$self" ] && continue
  if [ -f "$d/claude" ] && [ -x "$d/claude" ]; then real="$d/claude"; break; fi
done
IFS="$oldifs"
[ -n "$real" ] || { echo "[claude-session-sync] real claude not found on PATH" >&2; exit 1; }
exec "$real" "$@"
'@

if($Uninstall){
  if(Test-Path $binDir){ Remove-Item $binDir -Recurse -Force -EA SilentlyContinue; Write-Host "削除(shim): $binDir" -ForegroundColor Green }
} else {
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  Write-Shim (Join-Path $binDir 'claude.cmd') $cmdShim 'crlf'
  Write-Shim (Join-Path $binDir 'claude.ps1') $ps1Shim 'crlf'
  Write-Shim (Join-Path $binDir 'claude')     $shShim  'lf'
  Write-Host "導入(shim): $binDir (claude.cmd / claude.ps1 / claude)" -ForegroundColor Green
}

# ===== User PATH の先頭に css-bin を追加/削除 =====
# レジストリを直接読み書きして REG_EXPAND_SZ(ExpandString)種別と %VAR% 参照を壊さない([Environment]::SetEnvironmentVariable は REG_SZ 化してしまう)。
$norm = $binDir.TrimEnd('\')
$envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment',$true)
try{
  $raw  = [string]$envKey.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $kind = try{ $envKey.GetValueKind('Path') }catch{ [Microsoft.Win32.RegistryValueKind]::ExpandString }
  $parts = @($raw -split ';' | Where-Object { $_ -ne '' })
  $rest  = @($parts | Where-Object { $_.TrimEnd('\') -ine $norm })
  if($Uninstall){
    if($rest.Count -ne $parts.Count){ $envKey.SetValue('Path',($rest -join ';'),$kind); Write-Host "削除(PATH): $binDir" -ForegroundColor Green; $script:pathChanged=$true }
  } else {
    $new = (@($binDir)+$rest) -join ';'
    if($new -ne $raw){ $envKey.SetValue('Path',$new,$kind); Write-Host "導入(PATH 先頭に追加): $binDir" -ForegroundColor Green; $script:pathChanged=$true }
    else { Write-Host "PATH には既に先頭登録済み: $binDir" -ForegroundColor DarkGray }
  }
} finally { $envKey.Close() }
# WM_SETTINGCHANGE を通知して、新しく開くターミナル(Explorer 子プロセス)が再ログイン無しで新 PATH を拾えるようにする。
if($script:pathChanged){
  try{
    if(-not ([System.Management.Automation.PSTypeName]'CssEnv.Native').Type){
      Add-Type -Namespace CssEnv -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll",SetLastError=true,CharSet=System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd,uint Msg,System.UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out System.UIntPtr lpdwResult);
'@
    }
    $r=[System.UIntPtr]::Zero
    [void][CssEnv.Native]::SendMessageTimeout([System.IntPtr]0xffff,0x1a,[System.UIntPtr]::Zero,'Environment',2,5000,[ref]$r)
  }catch{}
}
# 現在のセッションでも即有効化
if($Uninstall){
  $env:PATH = (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ine $norm }) -join ';'
} elseif(($env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $norm){
  $env:PATH = "$binDir;$env:PATH"
}

if($Uninstall){
  Write-Host "解除しました。新しいターミナルを開くと完全に元へ戻ります(`claude -h` は公式のヘルプに戻ります)。" -ForegroundColor Cyan
} else {
  Write-Host "導入しました。新しいターミナル(PowerShell / cmd.exe / Git Bash いずれでも)を開くと、claude -h=履歴UI / claude -a=自動起動・リモート設定 / claude -r 等は公式のまま使えます。" -ForegroundColor Cyan
}
