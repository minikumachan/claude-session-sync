<#  claude-session-sync : 設定ハブ (Windows)  —  `claude -a`
    自動起動の管理に加え、同期(履歴/スキル/MCP)の状態・会話タイトル自動更新・
    共有の開始/再リンク・元の履歴先への復元 を一画面から扱う設定メニュー。
    描画は ASCII のみ(Ambiguous 幅文字を使わない=日本語環境でも崩れない)。
    リサイズ/フォーカス復帰時もキー入力を待たずに自動で再描画する。
    破壊的操作(リンク化/復元/MCP取り込み)は安全のため**手順を表示**し、その場では実行しない。  #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'
$claude   = Join-Path $env:USERPROFILE '.claude'
$cfgPath  = Join-Path $claude 'session-sync.local.conf'
$bootJson = Join-Path $claude 'session-sync.boot.json'
$sd       = $PSScriptRoot
if(-not (Test-Path $cfgPath)){ Write-Host '未設定です。先に setup を実行してください。' -ForegroundColor Yellow; return }

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Config($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Read-Entries { if(Test-Path $bootJson){ try{ $a=Get-Content $bootJson -Raw -Encoding utf8 | ConvertFrom-Json; if($a){ return @($a) } }catch{} }; @() }

function DispW([string]$s){ if($null -eq $s){ return 0 }; $w=0; foreach($ch in $s.ToCharArray()){ $c=[int][char]$ch
  if(($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF -and $c -ne 0x303F) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0xFFE0 -and $c -le 0xFFE6)){ $w+=2 } else { $w+=1 } }; $w }
function PadW([string]$s,[int]$w){ $d=DispW $s; if($d -lt $w){ $s + (' ' * ($w-$d)) } else { $s } }
function Clip([string]$s,[int]$n){ if($null -eq $s){ return '' }; if((DispW $s) -le $n){ return $s }; $o=''; $w=0; foreach($ch in $s.ToCharArray()){ $cw= if((DispW $ch) -eq 2){2}else{1}; if($w+$cw -gt $n-2){ break }; $o+=$ch; $w+=$cw }; $o+'..' }
function WriteRow([string]$text,[bool]$selected){ if($selected){ Write-Host (' > ' + $text) -ForegroundColor Black -BackgroundColor Gray } else { Write-Host ('   ' + $text) } }
function PauseKey { Write-Host ''; Write-Host '  何かキーを押すと戻ります。' -ForegroundColor DarkGray; [void][Console]::ReadKey($true) }

$cfg = Read-Config
$share = $cfg.share
$titleMap = @{}
$tps = @(); if($share){ $tps += (Join-Path $share 'sessions\titles.map') }; $tps += (Join-Path $claude 'sessions\titles.map')
foreach($tp in $tps){ if($tp -and (Test-Path $tp)){ foreach($l in (Get-Content $tp -Encoding utf8 -EA SilentlyContinue)){ $p=$l -split "`t",2; if($p.Count -eq 2 -and -not $titleMap.ContainsKey($p[0])){ $titleMap[$p[0]]=$p[1] } } } }
function Title-Of([string]$sid){ if($sid -and $titleMap.ContainsKey($sid)){ $titleMap[$sid] } else { '(無題)' } }
function LinkTarget([string]$name){ $it=Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue; if($it -and $it.LinkType){ $it.Target } else { $null } }

# ---------- 起動会話ピッカー / 項目エディタ ----------
function Pick-Session {
  $files = Get-ChildItem -Path (Join-Path $claude 'projects') -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue |
           Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } | Sort-Object LastWriteTime -Descending | Select-Object -First 15
  if(-not $files){ Write-Host '会話が見つかりません。' -ForegroundColor Yellow; Start-Sleep 2; return $null }
  $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  起動する会話を選ぶ' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    for($i=0;$i -lt $files.Count;$i++){ $sid=$files[$i].BaseName; WriteRow ("{0}   [{1}]" -f (Clip (Title-Of $sid) 48),$files[$i].LastWriteTime.ToString('MM/dd HH:mm')) ($i -eq $sel) }
    Write-Host ''; Write-Host '  Up/Down 選ぶ   Enter 決定   Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true)
    switch($k.Key){ 'UpArrow'{ if($sel -gt 0){$sel--} } 'DownArrow'{ if($sel -lt $files.Count-1){$sel++} } 'Enter'{ return $files[$sel].BaseName } 'Escape'{ return $null } }
  }
}
function Edit-Entry($src){
  $e = @{ type='new'; model='sonnet'; effort='medium'; remote=$true; sid='' }
  if($src){ foreach($k in $src.Keys){ $e[$k]=$src[$k] } }
  $typeOpts=@('new','last','resume'); $modelOpts=@('sonnet','opus','haiku','(指定IDを入力)'); $effOpts=@('(既定)','low','medium','high','xhigh','max'); $remOpts=@('on','off','ask')
  function RemStr($r){ if($r -is [bool]){ if($r){'on'}else{'off'} } elseif("$r" -eq 'True'){'on'} elseif("$r" -eq 'ask'){'ask'} elseif("$r" -eq 'False'){'off'} else { "$r" } }
  $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    $rows=@('type'); if($e.type -eq 'new'){ $rows+=@('model','effort') }; if($e.type -eq 'resume'){ $rows+=@('sid') }; $rows+=@('remote')
    if($sel -ge $rows.Count){ $sel=$rows.Count-1 }
    Clear-Host; Write-Host ''; Write-Host '  起動項目の編集' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    foreach($r in $rows){
      $i=[array]::IndexOf($rows,$r); $label=''; $val=''
      switch($r){
        'type'   { $label='種類'; $val= switch($e.type){'new'{'新規(壁打ち)'}'last'{'最近の会話を再開'}'resume'{'特定の会話'}} }
        'model'  { $label='モデル'; $val= if($e.model){$e.model}else{'sonnet'} }
        'effort' { $label='思考深度'; $val= if($e.effort){$e.effort}else{'(既定)'} }
        'sid'    { $label='会話'; $val= if($e.sid){ Clip (Title-Of "$($e.sid)") 44 }else{'(未選択 — Enterで選ぶ)'} }
        'remote' { $label='リモート'; $val= switch(RemStr $e.remote){'on'{'ON(スマホ操作)'}'off'{'OFF'}'ask'{'起動時に尋ねる'}} }
      }
      WriteRow ((PadW $label 10) + ': ' + $val) ($i -eq $sel)
    }
    Write-Host ''; Write-Host '  Up/Down 項目  Left/Right 値  Enter (会話)選択  S 決定  Esc 取消' -ForegroundColor DarkGray
    if($e.type -ne 'new'){ Write-Host '  ※ 最近/特定の会話は、その会話で使用中のモデル・思考深度をそのまま使います。' -ForegroundColor DarkGray }
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true); $cur=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return $null }
    if("$($k.KeyChar)" -match '^[sS]$'){ if($e.type -eq 'resume' -and -not $e.sid){ continue }; return $e }
    if($k.Key -eq 'Enter' -and $cur -eq 'sid'){ $p=Pick-Session; if($p){ $e.sid=$p }; continue }
    $dir= if($k.Key -eq 'LeftArrow'){ -1 } elseif($k.Key -eq 'RightArrow'){ 1 } else { 0 }
    if($dir -ne 0){
      switch($cur){
        'type'   { $i=([array]::IndexOf($typeOpts,$e.type)+$dir+$typeOpts.Count)%$typeOpts.Count; $e.type=$typeOpts[$i] }
        'model'  { $i=[array]::IndexOf($modelOpts,$e.model); if($i -lt 0){$i=0}; $i=($i+$dir+$modelOpts.Count)%$modelOpts.Count
                   if($modelOpts[$i] -eq '(指定IDを入力)'){ Clear-Host; $c=Read-Host 'モデルID(例 claude-sonnet-4-6) を入力'; if($c){ $e.model=$c } } else { $e.model=$modelOpts[$i] } }
        'effort' { $cu= if($e.effort){$e.effort}else{'(既定)'}; $i=[array]::IndexOf($effOpts,$cu); if($i -lt 0){$i=0}; $i=($i+$dir+$effOpts.Count)%$effOpts.Count; $e.effort= if($effOpts[$i] -eq '(既定)'){''}else{$effOpts[$i]} }
        'remote' { $cu=RemStr $e.remote; $i=[array]::IndexOf($remOpts,$cu); if($i -lt 0){$i=0}; $i=($i+$dir+$remOpts.Count)%$remOpts.Count; $e.remote= switch($remOpts[$i]){'on'{$true}'off'{$false}'ask'{'ask'}} }
      }
    }
  }
}
function EntryDisp($e){ switch("$($e.type)"){
    'new'    { "新規(壁打ち)  model=$(if($e.model){$e.model}else{'sonnet'})  思考=$(if($e.effort){$e.effort}else{'(既定)'})" }
    'last'   { "最近の会話を再開 (会話のモデル/深度を使用)" }
    'resume' { "特定: " + (Clip (Title-Of "$($e.sid)") 30) + " (会話のモデル/深度を使用)" }
    default  { "$($e.type)" } } }
function RemDisp($r){ if($r -is [bool]){ if($r){'ON'}else{'OFF'} } elseif("$r" -eq 'True'){'ON'} elseif("$r" -eq 'ask'){'尋ねる'} else {'OFF'} }

# ---------- 自動起動の管理(サブメニュー) ----------
function Manage-Autostart {
  $entries = New-Object System.Collections.ArrayList
  foreach($x in (Read-Entries)){ [void]$entries.Add(@{ type="$($x.type)"; model="$($x.model)"; effort="$($x.effort)"; sid="$($x.sid)"; remote=$x.remote }) }
  $cc = Read-Config; $checkMulti = ($cc.bootCheckMulti -ne 'false')
  $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    $rows=@(); for($i=0;$i -lt $entries.Count;$i++){ $rows+=@{kind='entry';idx=$i} }
    $rows+=@{kind='add'}; $rows+=@{kind='multi'}
    if($sel -ge $rows.Count){ $sel=$rows.Count-1 }; if($sel -lt 0){ $sel=0 }
    Clear-Host; Write-Host ''; Write-Host '  自動起動する会話の管理' -ForegroundColor Cyan
    Write-Host '  ============================================' -ForegroundColor Cyan; Write-Host ''
    for($r=0;$r -lt $rows.Count;$r++){
      $row=$rows[$r]; $text=''
      switch($row.kind){
        'entry' { $e=$entries[$row.idx]; $text="{0}) {1}  リモート={2}" -f ($row.idx+1),(EntryDisp $e),(RemDisp $e.remote) }
        'add'   { $text='＋ 新しい項目を追加' }
        'multi' { $text="[共通] 多重起動チェック : " + $(if($checkMulti){'オン(推奨)'}else{'オフ'}) }
      }
      WriteRow $text ($r -eq $sel)
    }
    Write-Host ''; Write-Host '  Up/Down 選ぶ  Enter 編集/追加/切替  D 削除  S 保存  Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true); $row=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return }
    if("$($k.KeyChar)" -match '^[sS]$'){
      $out=@()
      foreach($e in $entries){ $o=[ordered]@{ type=$e.type }; if($e.type -eq 'resume'){ $o.sid=$e.sid }; if($e.type -eq 'new'){ if($e.model){$o.model=$e.model}; if($e.effort){$o.effort=$e.effort} }; $o.remote=$e.remote; $out+=[pscustomobject]$o }
      [System.IO.File]::WriteAllText($bootJson,(ConvertTo-Json @($out) -Depth 6),(New-Object System.Text.UTF8Encoding($false)))
      $c2=Read-Config; $c2.bootCheckMulti= if($checkMulti){'true'}else{'false'}; Write-Config $c2
      Clear-Host; Write-Host '保存して登録します…' -ForegroundColor Cyan; & (Join-Path $sd 'install-autostart.ps1') -Apply; PauseKey; return
    }
    if("$($k.KeyChar)" -match '^[dD]$' -and $row.kind -eq 'entry'){ $entries.RemoveAt($row.idx); if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'Enter'){
      switch($row.kind){
        'entry' { $r=Edit-Entry $entries[$row.idx]; if($r){ $entries[$row.idx]=$r } }
        'add'   { $r=Edit-Entry $null; if($r){ [void]$entries.Add($r) } }
        'multi' { $checkMulti = -not $checkMulti }
      }
      continue
    }
    if($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow'){ if($row.kind -eq 'multi'){ $checkMulti = -not $checkMulti } }
  }
}

# ---------- 同期まわり ----------
function Show-SyncStatus { Clear-Host; Write-Host ''; Write-Host '  同期の状態' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; & (Join-Path $sd 'setup.ps1') -Status; PauseKey }
function Guide-Share {
  $c=Read-Config; Clear-Host; Write-Host ''; Write-Host '  共有を開始 / 再リンク(履歴・スキル)' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan
  Write-Host ("  現在: transport={0}  projects={1}  skills={2}  mcp={3}" -f $c.transport,$c.shareProjects,$c.shareSkills,$c.shareMcp)
  Write-Host ("  保存先(share): {0}" -f $c.share); Write-Host ''
  Write-Host '  安全のためここでは実行しません。次の手順で行ってください:' -ForegroundColor Yellow
  Write-Host '   1) Claude をすべて終了する(起動中はリンク化に失敗します)'
  Write-Host ("   2) 予行演習(内容確認):  pwsh -File `"{0}\setup.ps1`" -Phase link" -f $sd)
  Write-Host ("   3) 実行:                pwsh -File `"{0}\setup.ps1`" -Phase link -Yes" -f $sd)
  Write-Host ("   共有対象の変更:         pwsh -File `"{0}\setup.ps1`" -Skills -Mcp  など" -f $sd)
  PauseKey
}
function Guide-Mcp {
  Clear-Host; Write-Host ''; Write-Host '  MCP を共有(書き出し / 取り込み)' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan
  Write-Host '  ~/.claude.json はリンクせず mcpServers のみ同期します。'; Write-Host ''
  Write-Host ("   状態:     pwsh -File `"{0}\mcp-sync.ps1`" -Status" -f $sd)
  Write-Host ("   書き出し: pwsh -File `"{0}\mcp-sync.ps1`" -Export   (秘密があれば -Yes か -StripEnv)" -f $sd)
  Write-Host ("   取り込み: pwsh -File `"{0}\mcp-sync.ps1`" -Import -Yes  (自動バックアップ+検証)" -f $sd)
  PauseKey
}
function Guide-Restore {
  Clear-Host; Write-Host ''; Write-Host '  元の履歴先へ復元(共有リンクを解除)' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan
  foreach($n in 'projects','skills'){
    $t=LinkTarget $n; $old=Join-Path $claude ("{0}_local_old" -f $n)
    Write-Host ("  ~/.claude/{0}: {1}" -f $n, $(if($t){"リンク→ $t"}else{'ローカル(リンクなし)'}))
    if($t){
      Write-Host '   復元(Claude 終了後):' -ForegroundColor Yellow
      Write-Host ("     Remove-Item `"{0}`" -Force; " -f (Join-Path $claude $n)) -NoNewline
      if(Test-Path $old){ Write-Host ("Rename-Item `"{0}`" `"{1}`"" -f $old,$n) } else { Write-Host ("New-Item -ItemType Junction `"{0}`" -Target <元の場所>  ※ {1}_local_old が無いので退避先を確認" -f (Join-Path $claude $n),$n) }
    }
  }
  Write-Host ''; Write-Host '  ※ 実体データは共有フォルダ側に残ります(復元はリンクの解除のみ)。' -ForegroundColor DarkGray
  PauseKey
}
function Toggle-AutoTitle([bool]$on){ $c=Read-Config; $c.autoTitle= if($on){'true'}else{'false'}; Write-Config $c }

# ---------- トップ(設定ハブ) ----------
$autoTitle = ($cfg.autoTitle -ne 'false')
$items = @(
  @{ tag='自動起動 / リモート'; kind='autostart' },
  @{ tag='同期';               kind='autotitle' },
  @{ tag='表示・操作';         kind='status' },
  @{ tag='表示・操作';         kind='share' },
  @{ tag='表示・操作';         kind='mcp' },
  @{ tag='表示・操作';         kind='restore' },
  @{ tag='終了';               kind='exit' }
)
$sel=0; $lastW=[Console]::WindowWidth
while($true){
  $nEntries=(Read-Entries).Count
  Clear-Host; Write-Host ''
  Write-Host '  Claude セッション同期 — 設定   (claude -a)' -ForegroundColor Cyan
  Write-Host '  ===========================================' -ForegroundColor Cyan
  $prevTag=$null
  for($i=0;$i -lt $items.Count;$i++){
    if($items[$i].tag -ne $prevTag){ Write-Host ''; Write-Host ("  [{0}]" -f $items[$i].tag) -ForegroundColor DarkCyan; $prevTag=$items[$i].tag }
    $label=''
    switch($items[$i].kind){
      'autostart' { $label="自動起動する会話を管理   ({0}件)" -f $nEntries }
      'autotitle' { $label="会話タイトルの自動更新   : " + $(if($autoTitle){'ON'}else{'OFF'}) }
      'status'    { $label='同期の状態を表示(方式・保存先・共有中の項目)' }
      'share'     { $label='共有を開始 / 再リンク(履歴・スキル)' }
      'mcp'       { $label='MCP を共有(書き出し / 取り込み)' }
      'restore'   { $label='元の履歴先へ復元(リンク解除)' }
      'exit'      { $label='閉じる' }
    }
    WriteRow $label ($i -eq $sel)
  }
  Write-Host ''; Write-Host '  Up/Down 選ぶ   Enter 実行/編集   Left/Right トグル   Esc 終了' -ForegroundColor DarkGray
  while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
  if(-not [Console]::KeyAvailable){ continue }
  $k=[Console]::ReadKey($true); $kind=$items[$sel].kind
  if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
  if($k.Key -eq 'DownArrow'){ if($sel -lt $items.Count-1){$sel++}; continue }
  if($k.Key -eq 'Escape'){ Clear-Host; return }
  if($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow'){ if($kind -eq 'autotitle'){ $autoTitle= -not $autoTitle; Toggle-AutoTitle $autoTitle }; continue }
  if($k.Key -eq 'Enter'){
    switch($kind){
      'autostart' { Manage-Autostart }
      'autotitle' { $autoTitle= -not $autoTitle; Toggle-AutoTitle $autoTitle }
      'status'    { Show-SyncStatus }
      'share'     { Guide-Share }
      'mcp'       { Guide-Mcp }
      'restore'   { Guide-Restore }
      'exit'      { Clear-Host; return }
    }
    continue
  }
}
