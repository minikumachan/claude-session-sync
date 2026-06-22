<#  claude-session-sync : シェル統合(`claude -h`=履歴UI / `claude -a`=自動起動設定)(Windows)
    どのシェル(PowerShell / cmd.exe / Git Bash・MSYS)からでも `claude -h` が履歴UIになるよう、
    各シェルで「PATH 解決より優先される」仕組みで横取りする。実体 claude が【マシン PATH】(全ユーザ PATH より先)に
    在ると User PATH の shim では勝てないため、PATH 順に依存しない方式を各シェルで使う:
      (A) PowerShell: プロファイル(profile.ps1)に `claude` 関数(関数は PATH より優先)。
      (B) cmd.exe   : Command Processor の AutoRun で doskey マクロ `claude`(マクロは PATH より優先)。
      (C) Git Bash  : ~/.bashrc に `claude` 関数(関数は PATH より優先)。
      (D) 共通の実装: ~/.claude/css-bin の shim(claude.cmd / claude.ps1 / claude)に集約。上記(A)〜(C)はこの shim を呼ぶ。
          css-bin は User PATH 先頭にも入れる(プロファイル/rc 未読込時の保険)。
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
function c   { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" c @args }
function cfp { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" cfp @args }
function cp  { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" cp @args }
function cc  { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" cc @args }
function ch  { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" ch @args }
function ca  { & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" ca @args }
Remove-Item Alias:cp -Force -ErrorAction SilentlyContinue   # cp を固定パス起動に(既定の Copy-Item 別名より関数を優先)。コピーは Copy-Item を使用
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

# cmd.exe 用 cgo ランチャ(c/cfp/ch/ca の doskey から呼ぶ)。pwsh が無ければ powershell。引数(mode + 余分)を cgo.ps1 へ。
$cgoCmd = @'
@echo off
set "_ps1=%USERPROFILE%\.claude\skills\claude-session-sync\scripts\cgo.ps1"
where pwsh >nul 2>nul
if errorlevel 1 ( powershell -NoProfile -ExecutionPolicy Bypass -File "%_ps1%" %* ) else ( pwsh -NoProfile -ExecutionPolicy Bypass -File "%_ps1%" %* )
exit /b %ERRORLEVEL%
'@

if($Uninstall){
  if(Test-Path $binDir){ Remove-Item $binDir -Recurse -Force -EA SilentlyContinue; Write-Host "削除(shim): $binDir" -ForegroundColor Green }
} else {
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  Write-Shim (Join-Path $binDir 'claude.cmd') $cmdShim 'crlf'
  Write-Shim (Join-Path $binDir 'claude.ps1') $ps1Shim 'crlf'
  Write-Shim (Join-Path $binDir 'claude')     $shShim  'lf'
  Write-Shim (Join-Path $binDir 'cgo.cmd')    $cgoCmd  'crlf'
  Write-Host "導入(shim): $binDir (claude.cmd / claude.ps1 / claude / cgo.cmd)" -ForegroundColor Green
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

# ===== (C) cmd.exe: doskey マクロ(AutoRun)で claude と c/cfp/ch/ca を横取り =====
# 実体 claude がマシン PATH(= 全ユーザ PATH より先)に在ると、ユーザ PATH の css-bin では勝てない。
# cmd.exe では doskey マクロが PATH 解決より優先されるので、Command Processor の AutoRun でマクロを定義する。
$macros = @(
  'doskey claude="%USERPROFILE%\.claude\css-bin\claude.cmd" $*'
  'doskey c="%USERPROFILE%\.claude\css-bin\cgo.cmd" c $*'
  'doskey cfp="%USERPROFILE%\.claude\css-bin\cgo.cmd" cfp $*'
  'doskey cp="%USERPROFILE%\.claude\css-bin\cgo.cmd" cp $*'
  'doskey cc="%USERPROFILE%\.claude\css-bin\cgo.cmd" cc $*'
  'doskey ch="%USERPROFILE%\.claude\css-bin\cgo.cmd" ch $*'
  'doskey ca="%USERPROFILE%\.claude\css-bin\cgo.cmd" ca $*'
) -join ' & '
$cpKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Command Processor',$true)
if(-not $cpKey){ $cpKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Command Processor') }
try{
  $ar = [string]$cpKey.GetValue('AutoRun','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $ar = ($ar -replace 'doskey\s+(?:claude|cfp|cp|cc|ch|ca|c)=[^&]*','')   # 旧マクロを除去(冪等。長い名から順に)
  $ar = ($ar -replace '(\s*&\s*)+',' & ').Trim() ; $ar = ($ar -replace '^\s*&\s*','' -replace '\s*&\s*$','').Trim()
  if(-not $Uninstall){ $ar = if($ar){ "$ar & $macros" } else { $macros } }
  if([string]::IsNullOrWhiteSpace($ar)){ try{ $cpKey.DeleteValue('AutoRun',$false) }catch{} }
  else { $cpKey.SetValue('AutoRun',$ar,[Microsoft.Win32.RegistryValueKind]::ExpandString) }
  Write-Host "$(if($Uninstall){'削除'}else{'導入'})(cmd.exe doskey マクロ): claude / c / cfp / cp / cc / ch / ca" -ForegroundColor Green
}finally{ $cpKey.Close() }

# ===== (D) Git Bash / MSYS: ~/.bashrc の関数(PATH 解決より優先) =====
$bashrc = Join-Path $env:USERPROFILE '.bashrc'
$bashBlock = @'
# >>> claude-session-sync >>>
__cssps() { "$(command -v pwsh 2>/dev/null || command -v powershell)" -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.claude\skills\claude-session-sync\scripts\cgo.ps1" "$@"; }
claude() { "$HOME/.claude/css-bin/claude" "$@"; }
c()   { __cssps c "$@"; }
cfp() { __cssps cfp "$@"; }
cp()  { __cssps cp "$@"; }   # 固定パス起動(coreutils cp を上書き。コピーは command cp / /bin/cp)
cc()  { __cssps cc "$@"; }
ch()  { __cssps ch "$@"; }
ca()  { __cssps ca "$@"; }
# <<< claude-session-sync <<<
'@
$bc = if(Test-Path $bashrc){ [System.IO.File]::ReadAllText($bashrc) } else { '' }
$bc = [regex]::Replace($bc, "(?s)# >>> claude-session-sync >>>.*?# <<< claude-session-sync <<<\r?\n?", "")
if(-not $Uninstall){ $bc = $bc.TrimEnd() + "`n`n" + ($bashBlock -replace "`r`n","`n") + "`n" }
[System.IO.File]::WriteAllText($bashrc, ($bc -replace "`r`n","`n").TrimStart("`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "$(if($Uninstall){'削除'}else{'導入'})(Git Bash ~/.bashrc 関数): $bashrc" -ForegroundColor Green

if($Uninstall){
  Write-Host "解除しました。新しいターミナルを開くと完全に元へ戻ります(`claude -h` は公式のヘルプに戻ります)。" -ForegroundColor Cyan
} else {
  Write-Host "導入しました。PowerShell=関数 / cmd.exe=doskey / Git Bash=~/.bashrc の3系統で横取り(実体 claude がマシン PATH に在っても確実)。" -ForegroundColor Cyan
  Write-Host "ショートカット: c=通常起動 / cfp・cp=固定パス起動 / cc=直前の会話を再開 / ch=履歴UI / ca=設定。固定パス・リモートは『claude -a』→ 起動ショートカット設定 で。" -ForegroundColor Cyan
  Write-Host "※ cp は Copy-Item(PS)/ coreutils cp(bash)を上書きします。ファイルコピーは Copy-Item / command cp をご利用ください。" -ForegroundColor DarkGray
  Write-Host "★ 反映には【新しいターミナルを開き直して】ください(今 開いているウィンドウには反映されません)。" -ForegroundColor Yellow
}
