<#  claude-session-sync : 自動起動 / リモート設定の対話メニュー (Windows)
    `claude -a`(install-shell-wrap 導入時)から起動。矢印キーだけで設定できる簡易 GUI。
    値の収集のみ行い、保存・登録は install-autostart.ps1 に委譲する(ロジック重複なし)。  #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ Write-Host '未設定です。先に setup を実行してください。' -ForegroundColor Yellow; return }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$share = $cfg.share

# titles.map(共有→ローカルの順、先勝ち)
$titleMap = @{}
$tps = @()
if($share){ $tps += (Join-Path $share 'sessions\titles.map') }
$tps += (Join-Path $claude 'sessions\titles.map')
foreach($tp in $tps){ if($tp -and (Test-Path $tp)){ foreach($l in (Get-Content $tp -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t",2; if($a.Count -eq 2 -and -not $titleMap.ContainsKey($a[0])){ $titleMap[$a[0]]=$a[1] } } } }
function Title-Of([string]$sid){ if($titleMap.ContainsKey($sid)){ $titleMap[$sid] } else { '(無題)' } }
function Clip([string]$s,[int]$n){ if($null -eq $s){ return '' }; if($s.Length -gt $n){ $s.Substring(0,$n-1)+'…' } else { $s } }

# 特定の会話を選ぶサブピッカー(直近15件)
function Pick-Session {
  $files = Get-ChildItem -Path (Join-Path $claude 'projects') -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue |
           Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } |
           Sort-Object LastWriteTime -Descending | Select-Object -First 15
  if(-not $files){ Write-Host '会話が見つかりません。' -ForegroundColor Yellow; Start-Sleep 2; return $null }
  $sel = 0
  while($true){
    Clear-Host
    Write-Host '=== 毎回起動する会話を選ぶ ===' -ForegroundColor Cyan; Write-Host ''
    for($i=0; $i -lt $files.Count; $i++){
      $sid = $files[$i].BaseName
      $t = Clip (Title-Of $sid) 48
      $when = $files[$i].LastWriteTime.ToString('MM/dd HH:mm')
      $mark = if($i -eq $sel){'❯'}else{' '}
      $line = " {0} {1}   [{2}]" -f $mark,$t,$when
      if($i -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
    }
    Write-Host ''; Write-Host ' ↑↓ 選ぶ   Enter 決定   Esc 戻る' -ForegroundColor DarkGray
    $k = [Console]::ReadKey($true)
    switch($k.Key){
      'UpArrow'   { if($sel -gt 0){ $sel-- } }
      'DownArrow' { if($sel -lt $files.Count-1){ $sel++ } }
      'Enter'     { return $files[$sel].BaseName }
      'Escape'    { return $null }
    }
  }
}

# 各行の状態(states と現在 index)
$blStates = @('off','new','last','specific'); $blIdx = 1
$specificSid = $null
switch($cfg.bootLaunch){
  'off'  { $blIdx = 0 }
  'new'  { $blIdx = 1 }
  'last' { $blIdx = 2 }
  ''     { $blIdx = 0 }
  $null  { $blIdx = 0 }
  default{ if($cfg.bootLaunch){ $blIdx = 3; $specificSid = $cfg.bootLaunch } else { $blIdx = 0 } }
}
$brStates = @('false','ask','true'); $brIdx = 1
switch($cfg.bootRemote){ 'true'{ $brIdx=2 } 'false'{ $brIdx=0 } 'ask'{ $brIdx=1 } default{ $brIdx=1 } }
$cmStates = @('true','false'); $cmIdx = if($cfg.bootCheckMulti -eq 'false'){ 1 } else { 0 }
$rwStates = @('false','true'); $rwIdx = if($cfg.remoteWatch -eq 'true'){ 1 } else { 0 }

function BL-Label { switch($blStates[$blIdx]){ 'off'{'なし(起動しない)'} 'new'{'新規会話'} 'last'{'最近の会話を再開'} 'specific'{ "特定の会話: " + (Clip (Title-Of $specificSid) 40) } } }
function BR-Label { switch($brStates[$brIdx]){ 'false'{'オフ'} 'ask'{'起動時に尋ねる(8秒でオフ)'} 'true'{'常にオン(スマホ操作可)'} } }
function CM-Label { if($cmStates[$cmIdx] -eq 'true'){'オン(推奨)'}else{'オフ'} }
function RW-Label { if($rwStates[$rwIdx] -eq 'true'){'オン(スマホからトリガ起動)'}else{'オフ'} }

$rows = @(
  @{ key='ログイン時の自動起動'; label={ BL-Label } },
  @{ key='リモート(スマホ操作)'; label={ BR-Label } },
  @{ key='多重起動チェック';     label={ CM-Label } },
  @{ key='スマホからの起動(常駐)'; label={ RW-Label } }
)
$sel = 0

function Change([int]$dir){
  switch($sel){
    0 {
      $script:blIdx = ($script:blIdx + $dir + $blStates.Count) % $blStates.Count
      if($blStates[$script:blIdx] -eq 'specific'){
        $picked = Pick-Session
        if($picked){ $script:specificSid = $picked } else { $script:blIdx = 2 }   # 取消なら「最近の会話」へ
      }
    }
    1 { $script:brIdx = ($script:brIdx + $dir + $brStates.Count) % $brStates.Count }
    2 { $script:cmIdx = ($script:cmIdx + $dir + $cmStates.Count) % $cmStates.Count }
    3 { $script:rwIdx = ($script:rwIdx + $dir + $rwStates.Count) % $rwStates.Count }
  }
}

while($true){
  Clear-Host
  Write-Host '╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
  Write-Host '║   Claude 自動起動 / リモート設定  (claude -a)  ║' -ForegroundColor Cyan
  Write-Host '╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
  Write-Host ''
  for($i=0; $i -lt $rows.Count; $i++){
    $mark = if($i -eq $sel){'❯'}else{' '}
    $line = " {0} {1,-22} : {2}" -f $mark,$rows[$i].key,(& $rows[$i].label)
    if($i -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
  }
  Write-Host ''
  Write-Host ' ↑↓ 項目を選ぶ    ←→ 値を変える    Enter 保存して有効化    Esc 保存せず終了' -ForegroundColor DarkGray
  Write-Host ' (Tab=すべてオフにして解除)' -ForegroundColor DarkGray
  $k = [Console]::ReadKey($true)
  switch($k.Key){
    'UpArrow'    { if($sel -gt 0){ $sel-- } }
    'DownArrow'  { if($sel -lt $rows.Count-1){ $sel++ } }
    'LeftArrow'  { Change -1 }
    'RightArrow' { Change 1 }
    'Tab'        { $blIdx=0; $rwIdx=0; break }   # 解除(下の保存で off 反映)
    'Enter'      {
      $args = @()
      switch($blStates[$blIdx]){
        'off'      { $args += @('-Launch','off') }
        'new'      { $args += @('-Launch','new') }
        'last'     { $args += @('-Launch','last') }
        'specific' { if($specificSid){ $args += @('-Session',$specificSid) } else { $args += @('-Launch','last') } }
      }
      $args += @('-RemoteMode',$brStates[$brIdx])
      if($cmStates[$cmIdx] -eq 'true'){ $args += '-CheckMulti' } else { $args += '-NoCheckMulti' }
      if($rwStates[$rwIdx] -eq 'true'){ $args += '-Watch' } else { $args += '-NoWatch' }
      Clear-Host
      Write-Host '保存して登録します…' -ForegroundColor Cyan
      & (Join-Path $PSScriptRoot 'install-autostart.ps1') @args
      Write-Host ''
      Write-Host 'Enter で閉じる。' -ForegroundColor DarkGray
      [void][Console]::ReadKey($true)
      return
    }
    'Escape'     { Clear-Host; Write-Host '保存せず終了しました。' -ForegroundColor DarkGray; return }
  }
}
