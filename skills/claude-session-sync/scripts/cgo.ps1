<#  claude-session-sync : 起動ショートカット launcher (Windows)
    Mode: c=通常起動(現在地) / cfp=固定パス起動 / ch=履歴UI / ca=設定。
    conf(session-sync.local.conf)の launchPath / remoteC / remoteCfp を読む。
    c・cfp は設定でリモートコントロールが ON(既定)なら --remote-control を付与する。
    余分な引数はそのまま claude へ渡す。実体 claude は PATH から css-bin を除いて解決。
      cgo.ps1 c [args...] / cgo.ps1 cfp [args...] / cgo.ps1 ch / cgo.ps1 ca  #>
param([ValidateSet('c','cfp','ch','ca')][string]$Mode='c')
$ErrorActionPreference='SilentlyContinue'
try{ [Console]::OutputEncoding=(New-Object System.Text.UTF8Encoding($false)) }catch{}
$claude=Join-Path $env:USERPROFILE '.claude'
$scripts=Join-Path $claude 'skills\claude-session-sync\scripts'
$cssbin=Join-Path $claude 'css-bin'
$rest=$args

if($Mode -eq 'ch'){ & (Join-Path $scripts 'history-ui.ps1'); return }
if($Mode -eq 'ca'){ & (Join-Path $scripts 'autostart-ui.ps1'); return }

# conf 読み込み
$cfg=@{}; $cfgPath=Join-Path $claude 'session-sync.local.conf'
if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]]=($matches[2].TrimEnd("`r")) } } }

# 実体 claude(css-bin の shim を除外)
$real=(Get-Command claude.cmd,claude.exe -CommandType Application -All -EA SilentlyContinue | Where-Object { (Split-Path $_.Source -Parent) -ne $cssbin } | Select-Object -First 1).Source
if(-not $real){ Write-Host 'real claude が見つかりません(npm 等で導入してください)。' -ForegroundColor Red; return }

$cargs=@()
if($Mode -eq 'cfp'){
  $lp=$cfg.launchPath
  if($lp -and (Test-Path $lp)){ Set-Location -LiteralPath $lp }
  else { Write-Host "固定パス(cfp)が未設定/不在です。『claude -a』→ 起動ショートカット設定 で設定してください。" -ForegroundColor Yellow; if($lp){ Write-Host "  設定値: $lp" -ForegroundColor DarkGray } }
  if(($cfg.remoteCfp) -ne 'off'){ $cargs+='--remote-control' }   # 既定 ON(off のときだけ無効)
} else {  # c = 通常起動(現在地)
  if(($cfg.remoteC) -ne 'off'){ $cargs+='--remote-control' }     # 既定 ON
}
if($rest){ $cargs+=$rest }
& $real @cargs
