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
# titles.map から sid のタイトルを引く(共有先優先・ローカル fallback)。再開時に --name / --remote-control へ渡し、ローカル名もリモート名も日本語にする。
function TitleOf([string]$sid){
  if(-not $sid){ return $null }
  $paths=@(); if($cfg['share']){ $paths+=(Join-Path $cfg['share'] 'sessions\titles.map') }; $paths+=(Join-Path $claude 'sessions\titles.map')
  foreach($mp in $paths){ if($mp -and (Test-Path $mp)){ foreach($l in (Get-Content $mp -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t",2; if($a.Count -eq 2 -and $a[0] -eq $sid){ return $a[1] } } } }
  return $null
}
# 自動読み込み: master=autoRead(on)＋方式ごと autoRead<Item>(on)。既定はいずれも off(明示 on のときだけ有効)。
function WantAutoRead([string]$item){ if(($cfg['autoRead']) -ne 'on'){ return $false }; return (($cfg['autoRead'+$item]) -eq 'on') }
# 起動時に Claude へ送る「フォルダーを読んで全体像を把握」指示文(構成＋主要ノート)。パス未設定/不在なら $null。
function AutoReadInstruction(){
  $p=$cfg['autoReadPath']; if(-not $p){ return $null }
  if(-not (Test-Path -LiteralPath $p)){ Write-Host ("自動読み込み: 指定パスが見つかりません(スキップ): {0}" -f $p) -ForegroundColor Yellow; return $null }
  $kind= if($cfg['autoReadKind']){ $cfg['autoReadKind'] } else { 'フォルダー' }
  @"
作業を始める前に、次の場所の全体像を把握してください。
場所: $p（$kind）
フォルダー構成を確認し、_INDEX.md などの索引や主要なノートに目を通して、どこに何があるか・主要なテーマ・運用ルールを理解してください。把握できたら要点を簡潔に報告してください。
"@
}
# 確認モードの送信可否(↑/↓で選択、Enter で決定)。既定は「送信する」を選択。Esc=送信しない。
function ConfirmSend([string]$instr){
  $sel=0
  while($true){
    Clear-Host; Write-Host ''
    Write-Host '  起動時に以下を Claude へ送信します:' -ForegroundColor Cyan
    Write-Host '  --------------------------------------------------' -ForegroundColor Cyan
    foreach($ln in ($instr -split "`n")){ if($ln.Trim() -ne ''){ Write-Host ('  '+$ln) -ForegroundColor Gray } }
    Write-Host ''; Write-Host '  上記を送信しますか？' -ForegroundColor Yellow
    if($sel -eq 0){ Write-Host '   > 送信する' -ForegroundColor Black -BackgroundColor Gray; Write-Host '     送信しない' }
    else          { Write-Host '     送信する'; Write-Host '   > 送信しない' -ForegroundColor Black -BackgroundColor Gray }
    Write-Host ''; Write-Host '  ↑/↓ 選択   Enter 決定（Esc=送信しない）' -ForegroundColor DarkGray
    $k=[Console]::ReadKey($true)
    switch($k.Key){ 'UpArrow'{$sel=0} 'DownArrow'{$sel=1} 'Enter'{ return ($sel -eq 0) } 'Escape'{ return $false } }
  }
}

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
  $sid=$newest.BaseName
  $cargs+=@('--resume',$sid)
  # 再開時は titles.map の日本語タイトルをネイティブ表示名にも適用(プロンプト枠/resume と リモート名の英語化を防ぐ)
  $ttl= if(($cfg['titleApplyNative']) -ne 'off'){ TitleOf $sid } else { $null }
  if($ttl){ $cargs+=@('--name',$ttl) }
  if(WantRemote 'Cc'){ if($ttl){ $cargs+=@('--remote-control',$ttl) } else { $cargs+='--remote-control' } }
}
else {                                           # c = 通常起動(現在地)
  if(WantRemote 'C'){ $cargs+='--remote-control' }
}
if($rest){ $cargs+=$rest }
# 起動時フォルダ自動読み込み: 方式ごとに有効なら指示文を初回プロンプト(位置引数)として注入。confirm 時は起動前に送信可否を選ぶ。
$arItem= switch($Mode){ 'c'{'C'} 'cfp'{'Cfp'} 'cp'{'Cfp'} 'cc'{'Cc'} default{$null} }
if($arItem -and (WantAutoRead $arItem)){
  $instr=AutoReadInstruction
  if($instr){
    $send= if(($cfg['autoReadMode']) -eq 'auto'){ $true } else { ConfirmSend $instr }
    if($send){ $cargs+=$instr }
  }
}
& $real @cargs
