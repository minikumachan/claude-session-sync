<#  claude-session-sync : シェル統合(`claude -r` で全履歴ピッカー)(Windows)
    PowerShell プロファイルに `claude` 関数を追加し、`-r`/`--resume` を resume-all.ps1 に振り向ける。
    それ以外の引数は実体の claude へそのまま渡す。pwsh / Windows PowerShell 両方のプロファイルへ書き込む。
      install-shell-wrap.ps1            # 導入
      install-shell-wrap.ps1 -Uninstall # 削除  #>
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
$begin = '# >>> claude-session-sync (claude -r = all history) >>>'
$end   = '# <<< claude-session-sync <<<'
$block = @"
$begin
function claude {
  if (`$args.Count -gt 0 -and (`$args[0] -eq '-r' -or `$args[0] -eq '--resume')) {
    `$rest = if (`$args.Count -gt 1) { `$args[1..(`$args.Count-1)] } else { @() }
    & "`$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\resume-all.ps1" @rest
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
  # 既存ブロック除去(冪等)
  if($content -match [regex]::Escape($begin)){
    $content = [regex]::Replace($content, "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end) + "\r?\n?", "")
  }
  if(-not $Uninstall){ $content = $content.TrimEnd() + "`r`n`r`n" + $block + "`r`n" }
  Set-Content $pf $content -Encoding utf8
  Write-Host "$(if($Uninstall){'削除'}else{'導入'}): $pf" -ForegroundColor Green
}
Write-Host "新しいターミナルを開く(または プロファイルを再読込)と `claude -r` が全履歴ピッカーになります。" -ForegroundColor Cyan
