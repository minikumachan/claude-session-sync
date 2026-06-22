<#  claude-session-sync : 設定ハブ (Windows)  —  `claude -a`
    自動起動の管理に加え、同期(履歴/スキル/MCP)の状態・会話タイトル自動更新・
    共有の開始/再リンク・元の履歴先への復元 を一画面から扱う設定メニュー。
    描画は ASCII のみ(Ambiguous 幅文字を使わない=日本語環境でも崩れない)。
    リサイズ/フォーカス復帰時もキー入力を待たずに自動で再描画する。
    すべてメニュー(テキストGUI)から操作。破壊的操作(リンク化/復元/MCP取り込み)は
    予行演習や警告＋y/N 確認を挟んでから**その場で実行**する(コマンド文字列は表示しない)。  #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'
# 端末エンコーディングを UTF-8 に揃える(cmd.exe / Git Bash から起動された fresh プロセスや CP932 既定の端末でも日本語が化けないように)。
try{ [Console]::OutputEncoding=(New-Object System.Text.UTF8Encoding($false)) }catch{}
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
  $e = @{ type='new'; model='sonnet'; effort='medium'; remote=$true; sid=''; permission='default' }
  if($src){ foreach($k in $src.Keys){ $e[$k]=$src[$k] } }
  if(-not $e.permission){ $e.permission='default' }
  $typeOpts=@('new','last','resume'); $modelOpts=@('sonnet','opus','haiku','(指定IDを入力)'); $effOpts=@('(既定)','low','medium','high','xhigh','max'); $remOpts=@('on','off','ask')
  $permOpts=@('default','plan','acceptEdits','auto','dontAsk','bypassPermissions','full')
  function RemStr($r){ if($r -is [bool]){ if($r){'on'}else{'off'} } elseif("$r" -eq 'True'){'on'} elseif("$r" -eq 'ask'){'ask'} elseif("$r" -eq 'False'){'off'} else { "$r" } }
  function PermLabel($p){ switch("$p"){ 'default'{'既定(都度確認)'} 'plan'{'プラン(読取中心・安全)'} 'acceptEdits'{'編集を自動承認'} 'auto'{'自動(オート)'} 'dontAsk'{'確認しない'} 'bypassPermissions'{'⚠ 権限バイパス'} 'full'{'⚠⚠ 完全フリー(全回避・env取得/コピー可)'} default{"$p"} } }
  $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    $rows=@('type'); if($e.type -eq 'new'){ $rows+=@('model','effort') }; if($e.type -eq 'resume'){ $rows+=@('sid') }; $rows+=@('remote','permission')
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
        'permission' { $label='権限'; $val= PermLabel $e.permission }
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
        'permission' {
          $i=[array]::IndexOf($permOpts,"$($e.permission)"); if($i -lt 0){$i=0}; $i=($i+$dir+$permOpts.Count)%$permOpts.Count; $newp=$permOpts[$i]
          if($newp -eq 'bypassPermissions' -or $newp -eq 'full'){
            Clear-Host; Write-Host ''; Write-Host '  ⚠ 上位権限の確認' -ForegroundColor Red
            if($newp -eq 'full'){ Write-Host '  「完全フリー」は すべての権限チェックを回避し、env(秘密)値の取得・コピー・任意コマンド実行まで' -ForegroundColor Yellow; Write-Host '  無確認で許可します(--dangerously-skip-permissions 相当)。信頼できる用途のみで使用してください。' -ForegroundColor Yellow }
            else { Write-Host '  「権限バイパス」は 権限プロンプトを出さずにツールを実行します(bypassPermissions)。' -ForegroundColor Yellow }
            Write-Host ''; Write-Host '  本当にこの権限にしますか? [y/N]' -ForegroundColor Red
            $ans=[Console]::ReadKey($true); if("$($ans.KeyChar)" -match '^[yY]$'){ $e.permission=$newp }
          } else { $e.permission=$newp }
        }
      }
    }
  }
}
function EntryDisp($e){
  $pm = if($e.permission -and "$($e.permission)" -ne 'default'){ "  権限=$($e.permission)" } else { '' }
  $base = switch("$($e.type)"){
    'new'    { "新規(壁打ち)  model=$(if($e.model){$e.model}else{'sonnet'})  思考=$(if($e.effort){$e.effort}else{'(既定)'})" }
    'last'   { "最近の会話を再開 (会話のモデル/深度を使用)" }
    'resume' { "特定: " + (Clip (Title-Of "$($e.sid)") 30) + " (会話のモデル/深度を使用)" }
    default  { "$($e.type)" } }
  $base + $pm }
function RemDisp($r){ if($r -is [bool]){ if($r){'ON'}else{'OFF'} } elseif("$r" -eq 'True'){'ON'} elseif("$r" -eq 'ask'){'尋ねる'} else {'OFF'} }

# ---------- 自動起動の管理(サブメニュー) ----------
function Manage-Autostart {
  $entries = New-Object System.Collections.ArrayList
  foreach($x in (Read-Entries)){ [void]$entries.Add(@{ type="$($x.type)"; model="$($x.model)"; effort="$($x.effort)"; sid="$($x.sid)"; remote=$x.remote; permission=$(if($x.permission){"$($x.permission)"}else{'default'}) }) }
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
      foreach($e in $entries){ $o=[ordered]@{ type=$e.type }; if($e.type -eq 'resume'){ $o.sid=$e.sid }; if($e.type -eq 'new'){ if($e.model){$o.model=$e.model}; if($e.effort){$o.effort=$e.effort} }; $o.remote=$e.remote; if($e.permission -and "$($e.permission)" -ne 'default'){ $o.permission=$e.permission }; $out+=[pscustomobject]$o }
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

# ---------- 同期まわり(テキストGUI・その場で実行。破壊的操作は警告＋y/N確認) ----------
function Confirm-Danger([string]$title,[string[]]$lines){
  Clear-Host; Write-Host ''; Write-Host "  ⚠ 確認が必要な操作: $title" -ForegroundColor Red
  Write-Host '  ----------------------------------------' -ForegroundColor Red; Write-Host ''
  foreach($l in $lines){ Write-Host "  ・$l" -ForegroundColor Yellow }
  Write-Host ''; Write-Host '  実行する = y    /    やめる = n' -ForegroundColor Red
  $k=[Console]::ReadKey($true); return ("$($k.KeyChar)" -match '^[yY]$')
}
function Run-Show([string]$title,[scriptblock]$cmd){
  Clear-Host; Write-Host ''; Write-Host "  $title" -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
  $out=''; try { $out=(& $cmd 2>&1 | Out-String) } catch { $out="エラー: $($_.Exception.Message)" }
  foreach($line in ($out -split "`r?`n")){ if($line.Trim() -ne ''){ Write-Host "  $line" } }
  PauseKey
}
function Show-SyncStatus {
  $c=Read-Config
  function Comp($name,$flag){ $it=Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue; if($it -and $it.LinkType){ "共有中(リンク → $($it.Target))" } elseif($flag -eq 'true'){ '設定ONだが未リンク' } else { 'ローカル(共有なし)' } }
  Clear-Host; Write-Host ''; Write-Host '  同期の状態' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
  Write-Host ("  {0}: {1}" -f (PadW '同期方式(transport)' 22), $(if($c.transport){$c.transport}else{'folder'}))
  Write-Host ("  {0}: {1}" -f (PadW '保存先(共有フォルダ)' 22), $c.share)
  Write-Host ("  {0}: {1}" -f (PadW '会話履歴(projects)' 22), (Comp 'projects' $c.shareProjects))
  Write-Host ("  {0}: {1}" -f (PadW 'スキル(skills)' 22), (Comp 'skills' $c.shareSkills))
  Write-Host ("  {0}: {1}" -f (PadW 'MCP定義(mcp)' 22), $(if($c.shareMcp -eq 'true'){'共有ON(ファイル同期)'}else{'共有なし'}))
  Write-Host ("  {0}: {1}" -f (PadW '会話タイトル自動更新' 22), $(if($c.autoTitle -eq 'false'){'OFF'}else{'ON'}))
  Write-Host ("  {0}: {1}" -f (PadW 'デバイス切替の通知' 22), $(if($c.deviceSwitchNotice -eq 'false'){'OFF'}else{'ON'}))
  if($c.transport -eq 'git'){ Write-Host ("  {0}: {1}" -f (PadW 'git リモート' 22), $c.gitRemote) }
  PauseKey
}
function Do-Share {
  $c=Read-Config; $p=($c.shareProjects -ne 'false'); $s=($c.shareSkills -eq 'true'); $m=($c.shareMcp -eq 'true')
  $rows=@('projects','skills','mcp','preview','exec'); $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  共有を開始 / 変更 / 再リンク' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    Write-Host ("  保存先(共有): {0}" -f $c.share) -ForegroundColor DarkGray
    Write-Host '  対象を選び、まず[予行演習]→問題なければ[実行]。実行は破壊的(自動バックアップあり)。' -ForegroundColor DarkGray
    Write-Host '  ※ 実行前に他の Claude をすべて終了してください(起動中は失敗します)。' -ForegroundColor Yellow; Write-Host ''
    for($i=0;$i -lt $rows.Count;$i++){ $r=$rows[$i]; $t=''
      switch($r){
        'projects'{ $t=(PadW '会話履歴(projects)' 20)+': '+$(if($p){'共有する'}else{'共有しない'}) }
        'skills'  { $t=(PadW 'スキル(skills)' 20)+': '+$(if($s){'共有する'}else{'共有しない'}) }
        'mcp'     { $t=(PadW 'MCP定義(mcp)' 20)+': '+$(if($m){'共有する'}else{'共有しない'}) }
        'preview' { $t='▶ 予行演習(内容確認・変更しない)' }
        'exec'    { $t='● 実行する(バックアップして適用)' }
      }
      WriteRow $t ($i -eq $sel)
    }
    Write-Host ''; Write-Host '  Up/Down 選ぶ  Left/Right 切替  Enter 決定  Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true); $cur=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return }
    $tg = ($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow' -or $k.Key -eq 'Enter')
    if($tg -and $cur -eq 'projects'){ $p=-not $p; continue }
    if($tg -and $cur -eq 'skills'){ $s=-not $s; continue }
    if($tg -and $cur -eq 'mcp'){ $m=-not $m; continue }
    if($k.Key -eq 'Enter'){
      $flags=@(); $flags+=$(if($p){'-Projects'}else{'-NoProjects'}); $flags+=$(if($s){'-Skills'}else{'-NoSkills'}); $flags+=$(if($m){'-Mcp'}else{'-NoMcp'})
      if($cur -eq 'preview'){ Run-Show '予行演習(ドライラン: 変更しません)' { & (Join-Path $sd 'setup.ps1') @flags -Phase link } }
      elseif($cur -eq 'exec'){
        if(Confirm-Danger '共有の開始 / 再リンク' @('~/.claude/projects 等を共有フォルダへのリンクに置き換えます(破壊的)。','元データは *_backup_<時刻> と *_local_old に自動退避されます。','他の Claude が起動中だと失敗します。完全終了してから実行してください。')){
          Run-Show '実行結果' { & (Join-Path $sd 'setup.ps1') @flags -Phase all -Yes }
        }
      }
    }
  }
}
function Do-Mcp {
  $mcp=Join-Path $sd 'mcp-sync.ps1'; $rows=@('status','export','export_yes','import'); $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  MCP を共有(mcpServers のみ)' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    Write-Host '  ~/.claude.json はリンクせず mcpServers だけを同期します。' -ForegroundColor DarkGray; Write-Host ''
    for($i=0;$i -lt $rows.Count;$i++){ $r=$rows[$i]; $t= switch($r){'status'{'状態を表示'}'export'{'共有へ書き出す(Export)'}'export_yes'{'共有へ書き出す(秘密も含めて・要確認)'}'import'{'共有から取り込む(Import・破壊的・要確認)'}}; WriteRow $t ($i -eq $sel) }
    Write-Host ''; Write-Host '  Up/Down 選ぶ  Enter 実行  Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true); $cur=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return }
    if($k.Key -eq 'Enter'){
      switch($cur){
        'status'     { Run-Show 'MCP 状態' { & $mcp -Status } }
        'export'     { Run-Show 'MCP 書き出し(Export)' { & $mcp -Export } }
        'export_yes' { if(Confirm-Danger 'MCP 書き出し(秘密も含む)' @('MCP の env(APIキー等の秘密)も共有フォルダに書き出されます。','共有先が他人と共有されている場合は秘密が漏れる恐れがあります。')){ Run-Show 'MCP 書き出し(-Yes)' { & $mcp -Export -Yes } } }
        'import'     { if(Confirm-Danger 'MCP 取り込み(Import)' @('共有の mcpServers を ~/.claude.json に取り込みます(破壊的)。','自動でバックアップ(*.bak_<時刻>)を作成します。')){ Run-Show 'MCP 取り込み(-Import -Yes)' { & $mcp -Import -Yes } } }
      }
    }
  }
}
function Do-Restore {
  $rows=@('projects','skills'); $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  元の履歴先へ復元(共有リンクを解除)' -ForegroundColor Cyan; Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    Write-Host '  共有リンクを解除しローカルに戻します。実体データは共有側に残ります。' -ForegroundColor DarkGray
    Write-Host '  ※ 実行前に Claude を完全終了してください。' -ForegroundColor Yellow; Write-Host ''
    for($i=0;$i -lt $rows.Count;$i++){ $n=$rows[$i]; $t=LinkTarget $n; WriteRow ((PadW $n 12)+': '+$(if($t){"共有リンク → $t"}else{'ローカル(リンクなし)'})) ($i -eq $sel) }
    Write-Host ''; Write-Host '  Up/Down 選ぶ  Enter 復元  Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true); $name=$rows[$sel]
    if($k.Key -eq 'UpArrow'){ if($sel -gt 0){$sel--}; continue }
    if($k.Key -eq 'DownArrow'){ if($sel -lt $rows.Count-1){$sel++}; continue }
    if($k.Key -eq 'Escape'){ return }
    if($k.Key -eq 'Enter'){
      $it=Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue
      if(-not ($it -and $it.LinkType)){ Run-Show '復元' { Write-Output "~/.claude/$name は既にローカル(リンクなし)です。復元は不要です。" }; continue }
      $target=$it.Target; $old=Join-Path $claude ("{0}_local_old" -f $name)
      $note= if(Test-Path $old){ "退避フォルダ ${name}_local_old を書き戻します。" } else { "退避(_local_old)が無いため、共有から内容をコピーして復元します(時間がかかる場合あり)。" }
      if(Confirm-Danger "$name をローカルへ復元" @("~/.claude/$name の共有リンクを解除し、ローカルに戻します。","実体データは共有側($target)に残ります。",$note,"他の Claude が起動中だと失敗します。完全終了してから実行してください。")){
        Run-Show "$name の復元結果" {
          try {
            $lp=Join-Path $claude $name
            cmd /c rmdir "`"$lp`"" | Out-Null
            if(Test-Path $lp){ throw "リンクを解除できませんでした(使用中の可能性)。" }
            if(Test-Path $old){ Rename-Item $old $lp; Write-Output "✔ ${name}_local_old を ~/.claude/$name に書き戻しました。" }
            else { robocopy $target $lp /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null; Write-Output "✔ 共有($target)から ~/.claude/$name へコピーして復元しました。" }
            Write-Output "(共有フォルダ側のデータはそのまま残っています)"
          } catch { Write-Output "⛔ 失敗: $($_.Exception.Message)  Claude を完全終了してから再実行してください。" }
        }
      }
    }
  }
}
function Toggle-AutoTitle([bool]$on){ $c=Read-Config; $c.autoTitle= if($on){'true'}else{'false'}; Write-Config $c }
function Toggle-DevNotice([bool]$on){ $c=Read-Config; $c.deviceSwitchNotice= if($on){'true'}else{'false'}; Write-Config $c }

# ---------- トップ(設定ハブ) ----------
$autoTitle = ($cfg.autoTitle -ne 'false')
$devNotice = ($cfg.deviceSwitchNotice -ne 'false')
$items = @(
  @{ tag='自動起動 / リモート'; kind='autostart' },
  @{ tag='同期';               kind='autotitle' },
  @{ tag='同期';               kind='devnotice' },
  @{ tag='表示・操作';         kind='status' },
  @{ tag='表示・操作';         kind='checkdeps' },
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
      'devnotice' { $label="デバイス切替の通知       : " + $(if($devNotice){'ON'}else{'OFF'}) }
      'status'    { $label='同期の状態を表示(方式・保存先・共有中の項目)' }
      'checkdeps' { $label='環境チェック(必要なものが揃っているか確認)' }
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
  if($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow'){
    if($kind -eq 'autotitle'){ $autoTitle= -not $autoTitle; Toggle-AutoTitle $autoTitle }
    elseif($kind -eq 'devnotice'){ $devNotice= -not $devNotice; Toggle-DevNotice $devNotice }
    continue
  }
  if($k.Key -eq 'Enter'){
    switch($kind){
      'autostart' { Manage-Autostart }
      'autotitle' { $autoTitle= -not $autoTitle; Toggle-AutoTitle $autoTitle }
      'devnotice' { $devNotice= -not $devNotice; Toggle-DevNotice $devNotice }
      'status'    { Show-SyncStatus }
      'checkdeps' { Clear-Host; & (Join-Path $sd 'check-deps.ps1'); PauseKey }
      'share'     { Do-Share }
      'mcp'       { Do-Mcp }
      'restore'   { Do-Restore }
      'exit'      { Clear-Host; return }
    }
    continue
  }
}
