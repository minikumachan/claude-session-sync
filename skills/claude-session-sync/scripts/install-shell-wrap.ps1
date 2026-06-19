<#  claude-session-sync : シェル統合(`claude -h` で履歴ブラウザUI)(Windows)
    PowerShell プロファイルに `claude` 関数を追加し、`-h`/`--history` を history-ui.ps1 に振り向ける。
    `-r`(公式 --resume)を含むその他の引数は実体の claude へそのまま渡す(公式UIはそのまま)。
    pwsh / Windows PowerShell 両方のプロファイルへ書き込む。
      install-shell-wrap.ps1            # 導入
      install-shell-wrap.ps1 -Uninstall # 削除  #>
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
$begin = '# >>> claude-session-sync >>>'
$end   = '# <<< claude-session-sync <<<'
$block = @"
$begin
function claude {
  if (`$args.Count -ge 1 -and (`$args[0] -eq '-h' -or `$args[0] -eq '--history')) {
    & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\history-ui.ps1"
  } elseif (`$args.Count -ge 1 -and (`$args[0] -eq '-a' -or `$args[0] -eq '--autostart')) {
    & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\autostart-ui.ps1"
  } else {
    `$__rc = (Get-Command claude -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1).Source
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
  Write-Host "$(if($Uninstall){'削除'}else{'導入'}): $pf" -ForegroundColor Green
}
Write-Host "新しいターミナルを開く(またはプロファイル再読込)と、claude -h=履歴UI / claude -a=自動起動・リモート設定 / claude -r は公式のままになります。" -ForegroundColor Cyan
