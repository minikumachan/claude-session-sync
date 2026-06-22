<#  claude-session-sync : 必要環境のチェックと導入案内 (Windows)
    claude -h(履歴UI)/ claude -a(設定) を安定して使うために必要なものを確認し、
    不足があれば導入方法を案内する。Windows では PowerShell は標準搭載のため自動導入は行わず案内のみ。
      check-deps.ps1            # チェックして結果表示
      check-deps.ps1 -Quiet     # 問題が無ければ無出力(初回起動チェック用。要対応があるときだけ表示)  #>
[CmdletBinding()]
param([switch]$Quiet)
try{ [Console]::OutputEncoding=(New-Object System.Text.UTF8Encoding($false)) }catch{}
$miss=$false; $lines=@()
function L($s,$c){ $script:lines += ,@($s,$c) }

# --- PowerShell ---
if(Get-Command pwsh -EA SilentlyContinue){ L ("[OK] PowerShell 7 (pwsh): {0}" -f (Get-Command pwsh).Version) 'Green' }
elseif($PSVersionTable.PSVersion.Major -ge 5){ L ("[OK] Windows PowerShell {0}(pwsh の導入も推奨)" -f $PSVersionTable.PSVersion) 'Green' }
else { L "[要対応] PowerShell が見つかりません" 'Red'; $miss=$true }

# --- claude 本体(css-bin の shim は除外して実体を探す) ---
$cssbin=Join-Path $env:USERPROFILE '.claude\css-bin'
$rc=Get-Command claude.cmd,claude.exe -CommandType Application -All -EA SilentlyContinue | Where-Object { (Split-Path $_.Source -Parent) -ne $cssbin } | Select-Object -First 1
if($rc){ L ("[OK] claude 本体: {0}" -f $rc.Source) 'Green' }
else { L "[要対応] claude 本体が見つかりません" 'Red'; L "      → 導入: npm i -g @anthropic-ai/claude-code  (https://claude.com/claude-code)" 'Yellow'; $miss=$true }

# --- git(任意: git 同期方式を使う場合のみ) ---
if(Get-Command git -EA SilentlyContinue){ L ("[OK] git: {0}" -f (git --version)) 'Green' }
else { L "[任意] git は未導入(git 同期方式を使う場合のみ必要)" 'DarkGray' }

# --- シェル統合(claude -h/-a を全シェルで効かせる PATH shim) ---
if(Test-Path (Join-Path $cssbin 'claude.cmd')){ L ("[OK] シェル統合(PATH shim)導入済み: {0}" -f $cssbin) 'Green' }
else { L "[任意] シェル統合が未導入 → install-shell-wrap.ps1 で claude -h/-a を PowerShell/cmd/Git Bash 全対応に" 'Yellow' }

if($Quiet -and -not $miss){ exit 0 }   # 静音モード: 問題無しなら何も出さない

Write-Host ""
Write-Host "== claude-session-sync 環境チェック (Windows) ==" -ForegroundColor Cyan
Write-Host ""
foreach($e in $lines){ Write-Host ("  " + $e[0]) -ForegroundColor $e[1] }
Write-Host ""
if($miss){ Write-Host "上記の[要対応]を解消すると claude -h(履歴UI)/ claude -a(設定)が使えます。" -ForegroundColor Yellow; exit 1 }
else { Write-Host "すべて揃っています。claude -h(履歴UI)/ claude -a(設定)が使えます。" -ForegroundColor Green; exit 0 }
