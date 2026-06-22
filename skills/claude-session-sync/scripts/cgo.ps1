<#  claude-session-sync : 起動ショートカット launcher (Windows)
    Mode: c=通常起動(現在地) / cfp,cp=固定パス起動 / cc=直前の会話を再開(全デバイス横断) / ch=履歴UI / ca=設定。
    conf(session-sync.local.conf)の launchPath / remoteMode / remoteC / remoteCfp / remoteCc を読む。
    リモートコントロール: remoteMode=all なら全方式で常に付与、それ以外(items)は方式ごとの remote* を参照(既定 ON)。
    余分な引数はそのまま claude へ渡す。実体 claude は PATH から css-bin を除いて解決。
      cgo.ps1 c [args...] / cgo.ps1 cfp|cp [args...] / cgo.ps1 cc [args...] / cgo.ps1 ch / cgo.ps1 ca  #>
param([ValidateSet('c','cfp','cp','cc','ch','ca')][string]$Mode='c')
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
# リモート方針: all=全方式ON / items=方式ごと(既定 ON、off のときだけ無効)
function WantRemote([string]$item){ if(($cfg['remoteMode']) -eq 'all'){ return $true }; return (($cfg['remote'+$item]) -ne 'off') }

# 実体 claude(css-bin の shim を除外)
$real=(Get-Command claude.cmd,claude.exe -CommandType Application -All -EA SilentlyContinue | Where-Object { (Split-Path $_.Source -Parent) -ne $cssbin } | Select-Object -First 1).Source
if(-not $real){ Write-Host 'real claude が見つかりません(npm 等で導入してください)。' -ForegroundColor Red; return }

$cargs=@()
if($Mode -eq 'cfp' -or $Mode -eq 'cp'){          # 固定パス起動(cp は cfp の別名・remoteCfp を共有)
  $lp=$cfg['launchPath']
  if($lp -and (Test-Path $lp)){ Set-Location -LiteralPath $lp }
  else { Write-Host "固定パス起動の場所が未設定/不在です。『claude -a』→ 起動ショートカット設定 で設定してください。" -ForegroundColor Yellow; if($lp){ Write-Host "  設定値: $lp" -ForegroundColor DarkGray } }
  if(WantRemote 'Cfp'){ $cargs+='--remote-control' }
}
elseif($Mode -eq 'cc'){                          # 直前の会話を再開(全デバイス横断=同期済 projects 全体で最新)
  $pj=Join-Path $claude 'projects'
  $newest=Get-ChildItem -Path $pj -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue | Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $newest){ Write-Host '再開できる会話が見つかりません。' -ForegroundColor Yellow; return }
  $cargs+=@('--resume',$newest.BaseName)
  if(WantRemote 'Cc'){ $cargs+='--remote-control' }
}
else {                                           # c = 通常起動(現在地)
  if(WantRemote 'C'){ $cargs+='--remote-control' }
}
if($rest){ $cargs+=$rest }
& $real @cargs
