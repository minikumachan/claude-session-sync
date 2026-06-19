<#  claude-session-sync : 自動起動 / リモート設定の対話メニュー (Windows)
    `claude -a` から起動。矢印キーで複数の起動項目(種類/モデル/思考深度/リモート)を管理。
    起動項目は ~/.claude/session-sync.boot.json に保存し、登録は install-autostart.ps1 -Apply に委譲。  #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'
$claude   = Join-Path $env:USERPROFILE '.claude'
$cfgPath  = Join-Path $claude 'session-sync.local.conf'
$bootJson = Join-Path $claude 'session-sync.boot.json'
if(-not (Test-Path $cfgPath)){ Write-Host '未設定です。先に setup を実行してください。' -ForegroundColor Yellow; return }

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Config($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Read-Entries { if(Test-Path $bootJson){ try{ $a=Get-Content $bootJson -Raw -Encoding utf8 | ConvertFrom-Json; if($a){ return @($a) } }catch{} }; @() }
$cfg = Read-Config
$share = $cfg.share

# titles.map(共有→ローカル、先勝ち)
$titleMap = @{}
$tps = @(); if($share){ $tps += (Join-Path $share 'sessions\titles.map') }; $tps += (Join-Path $claude 'sessions\titles.map')
foreach($tp in $tps){ if($tp -and (Test-Path $tp)){ foreach($l in (Get-Content $tp -Encoding utf8 -EA SilentlyContinue)){ $p=$l -split "`t",2; if($p.Count -eq 2 -and -not $titleMap.ContainsKey($p[0])){ $titleMap[$p[0]]=$p[1] } } } }
function Title-Of([string]$sid){ if($sid -and $titleMap.ContainsKey($sid)){ $titleMap[$sid] } else { '(無題)' } }
function Clip([string]$s,[int]$n){ if($null -eq $s){ return '' }; if($s.Length -gt $n){ $s.Substring(0,$n-1)+'…' } else { $s } }

function Pick-Session {
  $files = Get-ChildItem -Path (Join-Path $claude 'projects') -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue |
           Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } | Sort-Object LastWriteTime -Descending | Select-Object -First 15
  if(-not $files){ Write-Host '会話が見つかりません。' -ForegroundColor Yellow; Start-Sleep 2; return $null }
  $sel = 0
  while($true){
    Clear-Host; Write-Host '=== 起動する会話を選ぶ ===' -ForegroundColor Cyan; Write-Host ''
    for($i=0; $i -lt $files.Count; $i++){
      $sid=$files[$i].BaseName; $t=Clip (Title-Of $sid) 48; $when=$files[$i].LastWriteTime.ToString('MM/dd HH:mm')
      $mark= if($i -eq $sel){'❯'}else{' '}; $line=" {0} {1}   [{2}]" -f $mark,$t,$when
      if($i -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
    }
    Write-Host ''; Write-Host ' ↑↓ 選ぶ   Enter 決定   Esc 戻る' -ForegroundColor DarkGray
    $k=[Console]::ReadKey($true)
    switch($k.Key){ 'UpArrow'{ if($sel -gt 0){$sel--} } 'DownArrow'{ if($sel -lt $files.Count-1){$sel++} } 'Enter'{ return $files[$sel].BaseName } 'Escape'{ return $null } }
  }
}

# 起動項目を編集(hashtable を受け取り編集後を返す。Esc は $null)
function Edit-Entry($src){
  $e = @{ type='new'; model='sonnet'; effort='medium'; remote=$true; sid='' }
  if($src){ foreach($k in $src.Keys){ $e[$k]=$src[$k] } }
  $typeOpts=@('new','last','resume'); $modelOpts=@('sonnet','opus','haiku','(指定IDを入力)'); $effOpts=@('(既定)','low','medium','high','xhigh','max'); $remOpts=@('on','off','ask')
  function RemStr($r){ if($r -is [bool]){ if($r){'on'}else{'off'} } elseif("$r" -eq 'True'){'on'} elseif("$r" -eq 'ask'){'ask'} elseif("$r" -eq 'False'){'off'} else { "$r" } }
  $sel=0
  while($true){
    # 行構成は種類で変わる
    $rows=@('type')
    if($e.type -eq 'new'){ $rows+=@('model','effort') }
    if($e.type -eq 'resume'){ $rows+=@('sid') }
    $rows+=@('remote')
    if($sel -ge $rows.Count){ $sel=$rows.Count-1 }
    Clear-Host
    Write-Host '=== 起動項目の編集 ===' -ForegroundColor Cyan; Write-Host ''
    foreach($r in $rows){
      $i=[array]::IndexOf($rows,$r); $mark= if($i -eq $sel){'❯'}else{' '}
      $label=''; $val=''
      switch($r){
        'type'   { $label='種類'; $val= switch($e.type){'new'{'新規(壁打ち)'}'last'{'最近の会話を再開'}'resume'{'特定の会話'}} }
        'model'  { $label='モデル'; $val= if($e.model){$e.model}else{'sonnet'} }
        'effort' { $label='思考深度'; $val= if($e.effort){$e.effort}else{'(既定)'} }
        'sid'    { $label='会話'; $val= Clip (Title-Of "$($e.sid)") 44; if(-not $e.sid){ $val='(未選択 — Enterで選ぶ)' } }
        'remote' { $label='リモート'; $val= switch(RemStr $e.remote){'on'{'ON(スマホ操作)'}'off'{'OFF'}'ask'{'起動時に尋ねる'}} }
      }
      $line=" {0} {1,-10}: {2}" -f $mark,$label,$val
      if($i -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
    }
    Write-Host ''
    Write-Host ' ↑↓ 項目  ←→ 値を変える  Enter (会話)選択  S 決定  Esc 取消' -ForegroundColor DarkGray
    if($e.type -ne 'new'){ Write-Host ' ※ 最近/特定の会話は、その会話で使用中のモデル・思考深度をそのまま使います。' -ForegroundColor DarkGray }
    $k=[Console]::ReadKey($true); $cur=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return $null }
    if("$($k.KeyChar)" -match '^[sS]$'){
      if($e.type -eq 'resume' -and -not $e.sid){ continue }   # 会話未選択なら保存不可
      return $e
    }
    if($k.Key -eq 'Enter' -and $cur -eq 'sid'){ $p=Pick-Session; if($p){ $e.sid=$p }; continue }
    $dir= if($k.Key -eq 'LeftArrow'){ -1 } elseif($k.Key -eq 'RightArrow'){ 1 } else { 0 }
    if($dir -ne 0){
      switch($cur){
        'type'   { $i=([array]::IndexOf($typeOpts,$e.type)+$dir+$typeOpts.Count)%$typeOpts.Count; $e.type=$typeOpts[$i] }
        'model'  { $i=([array]::IndexOf($modelOpts,$e.model)); if($i -lt 0){$i=0}; $i=($i+$dir+$modelOpts.Count)%$modelOpts.Count
                   if($modelOpts[$i] -eq '(指定IDを入力)'){ Clear-Host; $c=Read-Host 'モデルID(例 claude-sonnet-4-6) を入力'; if($c){ $e.model=$c } } else { $e.model=$modelOpts[$i] } }
        'effort' { $cu= if($e.effort){$e.effort}else{'(既定)'}; $i=([array]::IndexOf($effOpts,$cu)); if($i -lt 0){$i=0}; $i=($i+$dir+$effOpts.Count)%$effOpts.Count; $e.effort= if($effOpts[$i] -eq '(既定)'){''}else{$effOpts[$i]} }
        'remote' { $cu=RemStr $e.remote; $i=([array]::IndexOf($remOpts,$cu)); if($i -lt 0){$i=0}; $i=($i+$dir+$remOpts.Count)%$remOpts.Count; $e.remote= switch($remOpts[$i]){'on'{$true}'off'{$false}'ask'{'ask'}} }
      }
    }
  }
}

# 起動項目を読み込み(編集用 hashtable 配列)
$entries = New-Object System.Collections.ArrayList
foreach($x in (Read-Entries)){ [void]$entries.Add(@{ type="$($x.type)"; model="$($x.model)"; effort="$($x.effort)"; sid="$($x.sid)"; remote=$x.remote }) }
$checkMulti = ($cfg.bootCheckMulti -ne 'false')
$watch      = ($cfg.remoteWatch -eq 'true')

function EntryDisp($e){
  switch("$($e.type)"){
    'new'    { "新規(壁打ち)  model=$(if($e.model){$e.model}else{'sonnet'})  思考=$(if($e.effort){$e.effort}else{'(既定)'})" }
    'last'   { "最近の会話を再開 (会話のモデル/深度を使用)" }
    'resume' { "特定: " + (Clip (Title-Of "$($e.sid)") 30) + " (会話のモデル/深度を使用)" }
    default  { "$($e.type)" }
  }
}
function RemDisp($r){ if($r -is [bool]){ if($r){'ON'}else{'OFF'} } elseif("$r" -eq 'True'){'ON'} elseif("$r" -eq 'ask'){'尋ねる'} else {'OFF'} }

$sel=0
while($true){
  # 行: 各項目 / 追加 / multi / watch
  $rows=@(); for($i=0;$i -lt $entries.Count;$i++){ $rows+=@{kind='entry';idx=$i} }
  $rows+=@{kind='add'}; $rows+=@{kind='multi'}; $rows+=@{kind='watch'}
  if($sel -ge $rows.Count){ $sel=$rows.Count-1 }; if($sel -lt 0){ $sel=0 }
  Clear-Host
  Write-Host '╔════════════════════════════════════════════════╗' -ForegroundColor Cyan
  Write-Host '║   Claude 自動起動 / リモート設定   (claude -a)   ║' -ForegroundColor Cyan
  Write-Host '╚════════════════════════════════════════════════╝' -ForegroundColor Cyan
  Write-Host ''
  Write-Host ' ログオン時に起動する会話:' -ForegroundColor White
  for($r=0; $r -lt $rows.Count; $r++){
    $row=$rows[$r]; $mark= if($r -eq $sel){'❯'}else{' '}
    $text=''
    switch($row.kind){
      'entry' { $e=$entries[$row.idx]; $text="  {0}) {1}  リモート={2}" -f ($row.idx+1),(EntryDisp $e),(RemDisp $e.remote) }
      'add'   { $text='  ＋ 新しい項目を追加' }
      'multi' { $text=" [共通] 多重起動チェック : " + $(if($checkMulti){'オン(推奨)'}else{'オフ'}) }
      'watch' { $text=" [共通] スマホからの起動  : " + $(if($watch){'オン(常駐ウォッチャ)'}else{'オフ'}) }
    }
    $line=" {0}{1}" -f $mark,$text
    if($r -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
  }
  Write-Host ''
  Write-Host ' ↑↓ 選ぶ   Enter 編集/追加/切替   ←→ 共通設定の切替   D 項目削除   S 保存して有効化   Esc 中止' -ForegroundColor DarkGray
  $k=[Console]::ReadKey($true); $row=$rows[$sel]
  if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
  if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
  if($k.Key -eq 'Escape'){ Clear-Host; Write-Host '保存せず終了しました。' -ForegroundColor DarkGray; return }
  if("$($k.KeyChar)" -match '^[sS]$'){
    # 保存
    $out=@()
    foreach($e in $entries){
      $o=[ordered]@{ type=$e.type }
      if($e.type -eq 'resume'){ $o.sid=$e.sid }
      if($e.type -eq 'new'){ if($e.model){$o.model=$e.model}; if($e.effort){$o.effort=$e.effort} }
      $o.remote=$e.remote
      $out+=[pscustomobject]$o
    }
    [System.IO.File]::WriteAllText($bootJson,(ConvertTo-Json @($out) -Depth 6),(New-Object System.Text.UTF8Encoding($false)))
    $c2=Read-Config; $c2.bootCheckMulti= if($checkMulti){'true'}else{'false'}; $c2.remoteWatch= if($watch){'true'}else{'false'}; Write-Config $c2
    Clear-Host; Write-Host '保存して登録します…' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'install-autostart.ps1') -Apply
    Write-Host ''; Write-Host 'Enter で閉じる。' -ForegroundColor DarkGray; [void][Console]::ReadKey($true); return
  }
  if("$($k.KeyChar)" -match '^[dD]$' -and $row.kind -eq 'entry'){ $entries.RemoveAt($row.idx); if($sel -gt 0){$sel--}; continue }
  if($k.Key -eq 'Enter'){
    switch($row.kind){
      'entry' { $r=Edit-Entry $entries[$row.idx]; if($r){ $entries[$row.idx]=$r } }
      'add'   { $r=Edit-Entry $null; if($r){ [void]$entries.Add($r) } }
      'multi' { $script:checkMulti = -not $checkMulti }
      'watch' { $script:watch = -not $watch }
    }
    continue
  }
  if($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow'){
    if($row.kind -eq 'multi'){ $script:checkMulti = -not $checkMulti }
    elseif($row.kind -eq 'watch'){ $script:watch = -not $watch }
    continue
  }
}
