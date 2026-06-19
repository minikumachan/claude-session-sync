<#  claude-session-sync : 履歴ブラウザ UI (Windows)  —  `claude -h` から起動
    公式 `claude --resume` を踏襲。上部に枠付き検索ボックス(入力で即フィルタ)、その下にタブ
    ([全履歴=メイン+サブ全部][このプロジェクト][お気に入り][メインエージェント][サブエージェント])。各項目は 2行(タイトル / メタ)＋区切り線。
    操作: 文字入力で検索 / Backspace 消去 / Esc クリア(空なら終了) / ↑↓ 選択 / ←→ タブ /
          PageUp,PageDown ページ切替 / Ctrl+G ページ番号ジャンプ / Enter 再開 / Space 内容プレビュー /
          Tab=操作メニュー(★お気に入り / フォーク=複製分岐 / 文脈を引き継いで新規)
    遅延読込: 表示中の項目だけ内容を読む。 -SelfTest で1フレームをテキスト出力(検証用)。  #>
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
$claude=Join-Path $env:USERPROFILE '.claude'
$projects=Join-Path $claude 'projects'
if(-not (Test-Path $projects)){ Write-Host "履歴フォルダがありません: $projects" -ForegroundColor Yellow; return }
$cfgPath=Join-Path $claude 'session-sync.local.conf'
$cfg=@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){$cfg[$matches[1]]=($matches[2].TrimEnd("`r"))} } }
$devMap=@{}; $titleMap=@{}
if($cfg.share){
  $dm=Join-Path $cfg.share 'sessions\devices.map'
  if(Test-Path $dm){ foreach($l in (Get-Content $dm -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t",2; if($a.Count -eq 2){ $devMap[$a[0]]=$a[1] } } }
  $tm=Join-Path $cfg.share 'sessions\titles.map'
  if(Test-Path $tm){ foreach($l in (Get-Content $tm -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t",2; if($a.Count -eq 2){ $titleMap[$a[0]]=$a[1] } } }
}
# 共有先が無い場合のローカル titles.map(自動タイトル)。共有先の値があればそちら優先。
$ltm=Join-Path $claude 'sessions\titles.map'
if(Test-Path $ltm){ foreach($l in (Get-Content $ltm -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t",2; if($a.Count -eq 2 -and -not $titleMap.ContainsKey($a[0])){ $titleMap[$a[0]]=$a[1] } } }
# お気に入り(sid の集合)。共有先 + ローカルの和集合で読み込み、保存は両方へ書く(共有で全デバイス共通)。
$favs=@{}
$favLocal=Join-Path $claude 'sessions\favorites.txt'
$favShare= if($cfg.share){ Join-Path $cfg.share 'sessions\favorites.txt' } else { $null }
foreach($fp in @($favShare,$favLocal)){ if($fp -and (Test-Path $fp)){ foreach($l in (Get-Content $fp -Encoding utf8 -EA SilentlyContinue)){ $s=$l.Trim(); if($s){ $favs[$s]=$true } } } }
function Save-Favs {
  $content=(($favs.Keys | Sort-Object) -join "`n")+"`n"
  $targets=@(); if($favShare){ $targets+=$favShare }; $targets+=$favLocal
  foreach($tp in ($targets | Select-Object -Unique)){
    $dir=Split-Path $tp -Parent; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lk="$tp.lock"; $fsh=$null
    for($i=0;$i -lt 40;$i++){ try{ $fsh=[System.IO.File]::Open($lk,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None); break }catch{ Start-Sleep -Milliseconds 50 } }
    try{ [System.IO.File]::WriteAllText($tp,$content,(New-Object System.Text.UTF8Encoding($false))) } finally { if($fsh){ $fsh.Close() }; try{ [System.IO.File]::Delete($lk) }catch{} }
  }
}
function Toggle-Fav([string]$sid){ if($favs.ContainsKey($sid)){ [void]$favs.Remove($sid) } else { $favs[$sid]=$true }; Save-Favs }
# 使用中(アクセス中)の会話: 共有 locks/*.lock の session=<sid> を集める(12h超は残骸として無視)。sid -> machine。
function Load-Locks {
  $h=@{}
  if($cfg.share){
    $ld=Join-Path $cfg.share 'locks'
    if(Test-Path $ld){
      $now=Get-Date
      foreach($lf in (Get-ChildItem $ld -Filter *.lock -File -EA SilentlyContinue)){
        if(($now-$lf.LastWriteTime).TotalHours -gt 12){ continue }
        $c=Get-Content $lf.FullName -Raw -EA SilentlyContinue
        if($c -match 'session=([^\s]+)'){ $s=$matches[1]; if($s -and $s -ne '-'){ $m= if($c -match 'machine=([^\s]+)'){$matches[1]}else{'?'}; $h[$s]=$m } }
      }
    }
  }
  $h
}
function Locks-Sig($h){ if(-not $h){ return '' }; (($h.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object) -join '|') }
$script:lockSids = Load-Locks
$script:lockSig  = Locks-Sig $script:lockSids
# 自端末名(devices.map は deviceName、ロックは COMPUTERNAME を使うので比較は両方で行う)
$script:selfDev = if($cfg.deviceName){ $cfg.deviceName } else { $env:COMPUTERNAME }
# サブエージェント「実行中」とみなす鮮度(秒)。conf の subRunWin で変更可。
$script:subWin  = if($cfg.subRunWin -and ($cfg.subRunWin -match '^\d+$')){ [int]$cfg.subRunWin } else { 120 }
# 実行中サブエージェント検知: <sid>/subagents/agent-*.jsonl の更新が直近 subWin 秒以内なら実行中とみなす。
# 公式にサブエージェント用ロックは無いため transcript の鮮度を実行中シグナルにする(同期遅延の範囲で近似)。
# 返り値: parentSid -> @{ device; count; time }
function Load-RunSubs {
  $h=@{}; $now=Get-Date
  foreach($f in (Get-ChildItem $projects -Recurse -Filter 'agent-*.jsonl' -File -EA SilentlyContinue)){
    if((Split-Path $f.DirectoryName -Leaf) -ne 'subagents'){ continue }
    if(($now-$f.LastWriteTime).TotalSeconds -gt $script:subWin){ continue }
    $psid=SubParentSid $f
    $dev= if($devMap.ContainsKey($psid)){ $devMap[$psid] } else { DeviceFromKey (SubProjKey $f) }
    if($h.ContainsKey($psid)){ $e=$h[$psid]; $e.count++; if($f.LastWriteTime -gt $e.time){ $e.time=$f.LastWriteTime; $e.device=$dev } }
    else { $h[$psid]=@{ device=$dev; count=1; time=$f.LastWriteTime } }
  }
  $h
}
function RunSubs-Sig($h){ if(-not $h){ return '' }; (($h.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.device)x$($_.Value.count)" } | Sort-Object) -join '|') }
# 自端末判定: デバイス名は2系統(ロックは COMPUTERNAME、パス由来は Win/<user> 形式)あるので両方+別名で照合。
function Is-SelfDev([string]$d){ if(-not $d){ return $false }; ($d -eq $script:selfDev) -or ($d -eq $env:COMPUTERNAME) -or ($script:selfDevAlt -and $d -eq $script:selfDevAlt) }
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }
function Get-AllSessions {
  Get-ChildItem $projects -Recurse -Filter *.jsonl -EA SilentlyContinue | Where-Object {
    (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
    (Split-Path $_.DirectoryName -Leaf) -notlike '*session-sync-titlegen*' -and
    $_.BaseName -notlike 'agent-*' -and $_.BaseName -ne 'journal'
  } | Sort-Object LastWriteTime -Descending
}
# サブエージェント履歴: <mainSid>/subagents/agent-*.jsonl。親メインIDは祖父フォルダ名から取得(読み込み不要)。
function Get-SubAgents {
  Get-ChildItem $projects -Recurse -Filter 'agent-*.jsonl' -File -EA SilentlyContinue | Where-Object {
    (Split-Path $_.DirectoryName -Leaf) -eq 'subagents'
  } | Sort-Object LastWriteTime -Descending
}
function SubParentSid($f){ Split-Path (Split-Path $f.DirectoryName -Parent) -Leaf }     # subagents の親 = メインセッションID
function SubProjKey($f){ Split-Path (Split-Path (Split-Path $f.DirectoryName -Parent) -Parent) -Leaf }  # さらに上 = プロジェクトキー(符号化cwd)
function MsgText($o){ $c=$o.message.content; if($null -eq $c){return ''}; if($c -is [string]){return $c}; $p=@(); foreach($b in $c){ if($b.type -eq 'text' -and $b.text){ $p+=$b.text } }; ($p -join ' ') }
function DeviceFromCwd([string]$cwd){
  if(-not $cwd){ return 'unknown' }
  if($cwd -match '^[A-Za-z]:\\'){ $u=if($cwd -match '^[A-Za-z]:\\Users\\([^\\]+)'){$matches[1]}else{'?'}; return "Win/$u" }
  if($cwd -match '^/Users/([^/]+)'){ return "Mac/$($matches[1])" }
  if($cwd -match '^/home/([^/]+)'){ return "Linux/$($matches[1])" }
  if($cwd -match '^/root'){ return 'Linux/root' }
  return 'unknown'
}
# プロジェクトキー(符号化cwd 例 C--Users-Minikuma / -Users-clark)からデバイス名を推定(devices.map に無い時の保険)。
function DeviceFromKey([string]$key){
  if(-not $key){ return 'unknown' }
  if($key -match '^[A-Za-z]--Users-([A-Za-z0-9]+)'){ return "Win/$($matches[1])" }
  if($key -match '^-Users-([A-Za-z0-9]+)'){ return "Mac/$($matches[1])" }
  if($key -match '^-home-([A-Za-z0-9]+)'){ return "Linux/$($matches[1])" }
  if($key -match '^-root'){ return 'Linux/root' }
  return 'unknown'
}
function RelTime([datetime]$dt){
  $s=((Get-Date)-$dt).TotalSeconds
  if($s -lt 60){'たった今'} elseif($s -lt 3600){"$([int]($s/60))分前"} elseif($s -lt 86400){"$([int]($s/3600))時間前"}
  elseif($s -lt 2592000){"$([int]($s/86400))日前"} else {"$([int]($s/2592000))ヶ月前"}
}
function ProjShort([string]$dir){ $n=Split-Path $dir -Leaf; if($n.Length -gt 22){'…'+$n.Substring($n.Length-21)}else{$n} }
# 端末表示幅(全角CJK/絵文字=2桁)。枠線の桁ずれ防止に使用。
# ★☆(U+2605/2606)は East Asian Ambiguous で CJK 端末では記号グリフが全角(2桁)表示されることが多い。
# 過小評価すると行が想定より widくなり折返し→固定位置描画が崩れる(お気に入り行の★)。安全側=2 として数える。
function CharW([int]$c){
  if($c -eq 0x2605 -or $c -eq 0x2606){ return 2 }
  if($c -ge 0x1100 -and (
     $c -le 0x115F -or $c -eq 0x2329 -or $c -eq 0x232A -or
     ($c -ge 0x2E80 -and $c -le 0xA4CF -and $c -ne 0x303F) -or
     ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or
     ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or
     ($c -ge 0xFFE0 -and $c -le 0xFFE6) -or ($c -ge 0x1F300 -and $c -le 0x1FAFF) -or
     ($c -ge 0x20000 -and $c -le 0x3FFFD))){ return 2 }
  return 1
}
function DispWidth([string]$s){
  if(-not $s){ return 0 }
  $w=0
  for($i=0;$i -lt $s.Length;$i++){
    $c=[int][char]$s[$i]
    if($c -ge 0xD800 -and $c -le 0xDBFF -and ($i+1) -lt $s.Length){
      $lo=[int][char]$s[$i+1]; $cp=0x10000+(($c-0xD800)*0x400)+($lo-0xDC00); $i++; $w+=(CharW $cp)
    } else { $w+=(CharW $c) }
  }
  $w
}
# 表示幅(全角=2)で切り詰め(末尾…)。文字数でなく表示幅で切るので日本語タイトルが折り返さない。
function ClipW([string]$s,[int]$n){
  if($null -eq $s){ return '' }
  if((DispWidth $s) -le $n){ return $s }
  if($n -lt 1){ return '' }
  $o=''; $w=0
  for($i=0;$i -lt $s.Length;$i++){
    $c=[int][char]$s[$i]
    if($c -ge 0xD800 -and $c -le 0xDBFF -and ($i+1) -lt $s.Length){
      $lo=[int][char]$s[$i+1]; $cp=0x10000+(($c-0xD800)*0x400)+($lo-0xDC00); $cw=(CharW $cp)
      if($w+$cw -gt $n-1){ break }; $o+=([string]$s[$i]+[string]$s[$i+1]); $i++; $w+=$cw
    } else {
      $cw=(CharW $c); if($w+$cw -gt $n-1){ break }; $o+=[string]$s[$i]; $w+=$cw
    }
  }
  $o+'…'
}
# その場再描画(ちらつき防止): (0,$y)から色付きセグメントで全幅(W-1)上書きし、末尾を空白で埋めて残骸を消す。
# 改行を出さない(=スクロールしない)ので Clear-Host 不要。$padBg で行末余白の背景色(選択行の全幅ハイライト等)。
$script:scrW = 80
function PutSegs([int]$y,$segs,$padBg){
  if($y -lt 0 -or $y -ge [Console]::WindowHeight){ return }
  try{ [Console]::SetCursorPosition(0,$y) }catch{ return }
  $W=$script:scrW; $used=0
  foreach($s in $segs){
    if($used -ge $W-1){ break }
    $t="$($s.t)"; if($t -eq ''){ continue }
    $remain=($W-1)-$used; if((DispWidth $t) -gt $remain){ $t=(ClipW $t $remain) }
    $p=@{ Object=$t; NoNewline=$true }; if($s.fg){ $p['ForegroundColor']=$s.fg }; if($s.bg){ $p['BackgroundColor']=$s.bg }
    Write-Host @p; $used += (DispWidth $t)
  }
  $pad=($W-1)-$used
  if($pad -gt 0){ if($padBg){ Write-Host (' '*$pad) -NoNewline -BackgroundColor $padBg } else { Write-Host (' '*$pad) -NoNewline } }
}
function ClearBelow([int]$y){ $W=$script:scrW; $H=[Console]::WindowHeight; for($i=$y;$i -lt $H;$i++){ try{ [Console]::SetCursorPosition(0,$i); Write-Host (' '*($W-1)) -NoNewline }catch{} } }
$script:fullClear=$true
$script:scanCache=@{}
function Scan-Cached($f){
  if($script:scanCache.ContainsKey($f.FullName)){ return $script:scanCache[$f.FullName] }
  if(($f.BaseName -like 'agent-*') -and ((Split-Path $f.DirectoryName -Leaf) -eq 'subagents')){ return (Scan-Sub $f) }
  # 高速・上限付き読み込み(行移動を滑らかに): ReadLines は Get-Content より大幅に速く、
  # JSON 解析は該当しそうな行だけに絞る。上限行を超えたら件数に「+」を付けて打ち切り。
  $cwd='';$prev='';$ai='';$msgs=0;$cap=4000;$n=0;$more=$false
  try {
    foreach($line in [System.IO.File]::ReadLines($f.FullName)){
      if($n -ge $cap){ $more=$true; break }
      $n++
      if($line.Contains('"type":"user"') -or $line.Contains('"type":"assistant"')){ $msgs++ }
      if(-not ($cwd -and $ai -and $prev)){
        if($line.Contains('"cwd"') -or $line.Contains('ai-title') -or $line.Contains('"role":"user"')){
          try{$o=$line|ConvertFrom-Json}catch{$o=$null}
          if($o){
            if(-not $cwd -and $o.cwd){ $cwd=[string]$o.cwd }
            if(-not $ai -and $o.type -eq 'ai-title' -and $o.aiTitle){ $ai=[string]$o.aiTitle }
            if(-not $prev -and $o.message.role -eq 'user'){ $t=MsgText $o; if($t){ $prev=($t -replace '\s+',' ').Trim() } }
          }
        }
      }
    }
  } catch {}
  $sid=$f.BaseName
  $dev= if($devMap.ContainsKey($sid)){$devMap[$sid]}else{ DeviceFromCwd $cwd }
  $ttl= if($titleMap.ContainsKey($sid)){$titleMap[$sid]}elseif($ai){$ai}elseif($prev){$prev}else{'(無題)'}
  $msgStr= if($more){ "$msgs+" } else { "$msgs" }
  $r=[pscustomobject]@{ sid=$sid; device=$dev; title=$ttl; msgs=$msgStr; file=$f.FullName; time=$f.LastWriteTime; proj=(ProjShort $f.DirectoryName); isSub=$false; parentSid=''; agentType='' }
  $script:scanCache[$f.FullName]=$r; $r
}
# サブエージェント transcript の走査(種別=attributionAgent / タイトル=最初の依頼文 / 実行元デバイス)。
function Scan-Sub($f){
  $atype='';$first='';$msgs=0;$cwd='';$cap=2000;$n=0;$more=$false
  try {
    foreach($line in [System.IO.File]::ReadLines($f.FullName)){
      if($n -ge $cap){ $more=$true; break }
      $n++
      if($line.Contains('"type":"user"') -or $line.Contains('"type":"assistant"')){ $msgs++ }
      if(-not ($atype -and $first -and $cwd)){
        if($line.Contains('attributionAgent') -or $line.Contains('"role":"user"') -or $line.Contains('"cwd"')){
          try{$o=$line|ConvertFrom-Json}catch{$o=$null}
          if($o){
            if(-not $atype -and $o.attributionAgent){ $atype=[string]$o.attributionAgent }
            if(-not $cwd -and $o.cwd){ $cwd=[string]$o.cwd }
            if(-not $first -and $o.message.role -eq 'user'){ $t=MsgText $o; if($t){ $first=($t -replace '\s+',' ').Trim() } }
          }
        }
      }
    }
  } catch {}
  $psid=SubParentSid $f
  if(-not $atype){ $atype='subagent' }
  $dev= if($devMap.ContainsKey($psid)){ $devMap[$psid] } elseif($cwd){ DeviceFromCwd $cwd } else { DeviceFromKey (SubProjKey $f) }
  $ttl= if($first){ $first } else { "($atype)" }
  $msgStr= if($more){ "$msgs+" } else { "$msgs" }
  $r=[pscustomobject]@{ sid=$f.BaseName; device=$dev; title=$ttl; msgs=$msgStr; file=$f.FullName; time=$f.LastWriteTime; proj=(ProjShort $f.DirectoryName); isSub=$true; parentSid=$psid; agentType=$atype }
  $script:scanCache[$f.FullName]=$r; $r
}
$palette=@('Cyan','Green','Yellow','Magenta','Blue','Red','DarkCyan','DarkGreen','DarkYellow','DarkMagenta','White')
function ColorFor([string]$dev){ $h=0; foreach($ch in $dev.ToCharArray()){ $h=($h*31+[int]$ch) }; $palette[[Math]::Abs($h)%$palette.Count] }

$cwdKey=Encode((Get-Location).Path)
# kind='all'=メイン+サブ全部(時系列)、'main'=通常会話(allSessions)、'sub'=サブエージェント(allSubAgents)。
$tabs=@(
  @{ name='全履歴';            kind='all'  },
  @{ name='このプロジェクト';   kind='main'; sel={ param($f) (Split-Path $f.DirectoryName -Leaf) -eq $cwdKey } },
  @{ name='お気に入り';        kind='main'; sel={ param($f) $favs.ContainsKey($f.BaseName) } },
  @{ name='メインエージェント'; kind='main'; sel={ param($f) $true } },
  @{ name='サブエージェント';   kind='sub'  }
)
$allSessions=@(Get-AllSessions)
$allSubAgents=@(Get-SubAgents)
$script:selfDevAlt = DeviceFromCwd $env:USERPROFILE   # 自端末のパス由来名(例 Win/Minikuma)。「（このデバイス）」照合用。
$script:runSubs=Load-RunSubs; $script:runSig=RunSubs-Sig $script:runSubs
function Tab-Files($ti,$search){
  $kind=$tabs[$ti].kind
  if($kind -eq 'all'){ $f=@($allSessions + $allSubAgents | Sort-Object LastWriteTime -Descending) }
  elseif($kind -eq 'sub'){ $f=@($allSubAgents) }
  else { $f=@($allSessions | Where-Object { & $tabs[$ti].sel $_ }) }
  if($search){
    if($kind -eq 'sub'){
      $f=@($f | Where-Object { (SubParentSid $_) -like "$search*" -or ($script:scanCache.ContainsKey($_.FullName) -and $script:scanCache[$_.FullName].title -match [regex]::Escape($search)) })
    } else {
      $f=@($f | Where-Object { (Split-Path $_.DirectoryName -Leaf) -match [regex]::Escape($search) -or $_.BaseName -like "$search*" -or ($script:scanCache.ContainsKey($_.FullName) -and $script:scanCache[$_.FullName].title -match [regex]::Escape($search)) })
    }
  }
  # 同一会話(同 sid)が複数フォルダに在る場合(別フォルダ/別デバイスで再開した会話)は重複排除し最新(mtime最大)の1件だけ残す。
  # 一覧は mtime 降順なので「最初に現れたもの=最新」を残せばよい。お気に入りでも最新の表記で1件に集約される。
  $seen=@{}; $f=@($f | Where-Object { if($seen.ContainsKey($_.BaseName)){ $false } else { $seen[$_.BaseName]=$true; $true } })
  $f
}
function ItemsPerPage { [Math]::Max(2,[int][Math]::Floor(([Console]::WindowHeight-8)/3)) }

# お気に入りは ★ をタイトル前に付けて表示(描画と部分更新で共用)。
function RowTitle($info,$dw){
  $star= if($favs.ContainsKey($info.sid)){'★ '}else{''}
  $budget=$dw-2-(DispWidth $star); if($budget -lt 4){ $budget=4 }   # 先頭"> "/"  "=2桁
  $star+(ClipW $info.title $budget)
}

# ---- 描画(枠付き検索 + タブ + 2行/区切り線) ----
function Draw([int]$ti,[object[]]$files,[int]$sel,[int]$pageTop,[int]$rows,[string]$search){
  $w=[Console]::WindowWidth; if($w -lt 44){$w=80}; $script:scrW=$w; $dw=[Math]::Min($w-2,78); $boxW=[Math]::Min($dw,56)
  # 全消去フレーム(初回/リサイズ/タブ/ページ/サブ画面復帰)でのみ使用中ロックを読み直す。矢印移動は IO 無しでその場上書き=ちらつかない。
  if($script:fullClear){ $script:lockSids = Load-Locks; $script:lockSig = Locks-Sig $script:lockSids; $script:runSubs = Load-RunSubs; $script:runSig = RunSubs-Sig $script:runSubs; Clear-Host; $script:fullClear=$false }
  $y=0
  # 検索ボックス(枠付き)
  $label='─ 🔍 検索 '
  PutSegs $y @(@{t=("┌"+$label+('─'*[Math]::Max(0,$boxW-(DispWidth $label)))+"┐"); fg='DarkCyan'}); $y++
  $inner=$search+'█'; $pad=[Math]::Max(0,$boxW-1-(DispWidth $inner))
  PutSegs $y @(@{t="│ "; fg='DarkCyan'},@{t=$inner; fg='White'},@{t=((' '*$pad)+"│"); fg='DarkCyan'}); $y++
  PutSegs $y @(@{t=("└"+('─'*$boxW)+"┘"); fg='DarkCyan'}); $y++
  # タブ
  $tabSegs=@()
  for($i=0;$i -lt $tabs.Count;$i++){
    if($i -eq $ti){ $tabSegs+=@{t=" $($tabs[$i].name) "; fg='Black'; bg='Cyan'} } else { $tabSegs+=@{t=" $($tabs[$i].name) "; fg='DarkGray'} }
    $tabSegs+=@{t='  '}
  }
  PutSegs $y $tabSegs; $y++
  $total=$files.Count; $page=[Math]::Floor($pageTop/$rows)+1; $pages=[Math]::Max(1,[Math]::Ceiling($total/$rows))
  # ページ切替ボタン(使用可なら反転=ボタン風、端では淡色)＋番号ジャンプの案内。
  $prevOn=($page -gt 1); $nextOn=($page -lt $pages)
  $pgSegs=@(
    @{t='Enter=続き   '; fg='DarkGray'},
    @{t=' < 前 '; fg=$(if($prevOn){'Black'}else{'DarkGray'}); bg=$(if($prevOn){'Gray'}else{$null})},
    @{t="  ページ $page/$pages (全 $total件)  "; fg='Gray'},
    @{t=' 次 > '; fg=$(if($nextOn){'Black'}else{'DarkGray'}); bg=$(if($nextOn){'Gray'}else{$null})},
    @{t='   PgUp/PgDn=切替 ・ Ctrl+G=番号ジャンプ'; fg='DarkGray'}
  )
  PutSegs $y $pgSegs; $y++
  PutSegs $y @(@{t=(' '+('─'*$dw)); fg='DarkGray'}); $y++
  for($r=0;$r -lt $rows;$r++){
    $idx=$pageTop+$r
    if($idx -ge $total){ break }
    $info=Scan-Cached $files[$idx]
    $ttl=RowTitle $info $dw
    if($idx -eq $sel){ PutSegs $y @(@{t=("> "+$ttl); fg='White'; bg='DarkBlue'}) 'DarkBlue' } else { PutSegs $y @(@{t=("  "+$ttl); fg='Gray'}) }
    $y++
    # メタ行(先頭=device(サブは種別)色 + 残り + 状態マーカー)。PutSegs が全幅で上書き、折り返さない。
    $rest=" │ {0} msg │ {1} │ {2}" -f $info.msgs,(RelTime $info.time),$info.proj
    $mk=''; $mkFg='Red'
    if($info.isSub){
      # サブエージェント行: 実行元メイン会話 + 実行元デバイス + 実行中状態
      $head="🤖 "+$info.agentType; $headCol=(ColorFor $info.agentType)
      $isRun=(((Get-Date)-$info.time).TotalSeconds -le $script:subWin)
      $pt= if($titleMap.ContainsKey($info.parentSid) -and $titleMap[$info.parentSid]){ ClipW $titleMap[$info.parentSid] 24 } else { '(無題のメイン)' }
      $sd=$info.device; $self= if(Is-SelfDev $sd){'（このデバイス）'}else{''}
      if($isRun){ $mk="  [実行中 ← 「$pt」メインから ・ 実行元: $sd$self]"; $mkFg='DarkYellow' }
      else      { $mk="  [元: 「$pt」 ・ $sd]"; $mkFg='DarkGray' }
    } else {
      # メイン行: ①アクセス中(ロック) ②ロック無しでサブエージェント実行中 ③どちらも無し=表示なし
      $head=$info.device; $headCol=(ColorFor $info.device)
      if($script:lockSids.ContainsKey($info.sid)){
        $lm=$script:lockSids[$info.sid]
        $mk="  [アクセス中: $lm$(if(Is-SelfDev $lm){'（このデバイス）'})]"; $mkFg='Red'
      } elseif($script:runSubs.ContainsKey($info.sid)){
        $rs=$script:runSubs[$info.sid]; $rd=$rs.device; $cnt= if($rs.count -gt 1){"（×$($rs.count)）"}else{''}
        $self= if(Is-SelfDev $rd){'（このデバイス）'}else{''}
        $mk="  [$rd でサブエージェント実行中$cnt$self]"; $mkFg='DarkYellow'
      }
    }
    $segs=@(@{t="   "},@{t=$head; fg=$headCol})
    if($mk){ $segs+=@{t=$rest; fg='DarkGray'}; $segs+=@{t=$mk; fg=$mkFg} } else { $segs+=@{t=$rest; fg='DarkGray'} }
    PutSegs $y $segs; $y++
    PutSegs $y @(@{t=(' '+('─'*$dw)); fg='DarkGray'}); $y++
  }
  PutSegs $y @(@{t="文字=検索 ↑↓=選択 ←→=タブ Enter=再開 Tab=操作 Space=内容 PgUp/PgDn=頁 Ctrl+G=頁番号 Esc=終了"; fg='DarkGray'}); $y++
  ClearBelow $y
  try{ [Console]::SetCursorPosition(0,[Math]::Max(0,[Console]::WindowHeight-1)) }catch{}
}
# 軽量ハイライト移動: 選択行のタイトル行だけ書き換える(全行再描画しないので軽い)。
# 折り返しが無い前提(ClipW/PutSegs)なので各項目は3行ぴったり=固定位置 Y=6+r*3 が常に正しい。
function Paint-Title([int]$r,[int]$idx,$files,[int]$sel,[int]$dw){
  if($idx -lt 0 -or $idx -ge $files.Count){ return }
  if($r -lt 0 -or (6+$r*3) -ge [Console]::WindowHeight){ return }
  $ttl=RowTitle (Scan-Cached $files[$idx]) $dw
  if($idx -eq $sel){ PutSegs (6+$r*3) @(@{t=("> "+$ttl); fg='White'; bg='DarkBlue'}) 'DarkBlue' }
  else { PutSegs (6+$r*3) @(@{t=("  "+$ttl); fg='Gray'}) }
}

if($SelfTest){
  $files=@(Tab-Files 0 'syncthing'); if($files.Count -eq 0){ $files=@(Tab-Files 0 '') }
  $n=[Math]::Min(2,$files.Count); $sb=New-Object System.Text.StringBuilder
  $boxW=56; $label='─ 🔍 検索 '; $inner='syncthing█'
  [void]$sb.AppendLine("┌"+$label+('─'*[Math]::Max(0,$boxW-(DispWidth $label)))+"┐")
  [void]$sb.AppendLine("│ "+$inner+(' '*[Math]::Max(0,$boxW-1-(DispWidth $inner)))+"│")
  [void]$sb.AppendLine("└"+('─'*$boxW)+"┘")
  [void]$sb.AppendLine(" [全履歴]    このプロジェクト    お気に入り    メインエージェント    サブエージェント")
  [void]$sb.AppendLine(' '+('─'*54))
  [void]$sb.AppendLine(" Enter=続き    < 前    ページ 1/3 (全 $($files.Count)件)    次 >    PgUp/PgDn=切替 ・ Ctrl+G=番号ジャンプ")
  [void]$sb.AppendLine(' '+('─'*54))
  for($r=0;$r -lt $n;$r++){ $info=Scan-Cached $files[$r]
    [void]$sb.AppendLine($(if($r -eq 0){'> '}else{'  '})+(ClipW $info.title 54))
    [void]$sb.AppendLine(("   {0} │ {1} msg │ {2} │ {3}" -f $info.device,$info.msgs,(RelTime $info.time),$info.proj))
    [void]$sb.AppendLine(' '+('─'*54)) }
  $sb.ToString() | Write-Output; return
}

function Preview($file){
  Clear-Host
  Write-Host "── 内容プレビュー(任意キーで戻る)──" -ForegroundColor Cyan
  $n=0
  foreach($line in (Get-Content $file -Encoding utf8 -EA SilentlyContinue)){
    if($n -ge ([Console]::WindowHeight-3)){ Write-Host "  …(以降は Enter で開いてください)" -ForegroundColor DarkGray; break }
    if(-not $line.Trim()){continue}; try{$o=$line|ConvertFrom-Json}catch{continue}
    $role=$o.message.role; if($role -ne 'user' -and $role -ne 'assistant'){continue}
    $t=MsgText $o; if(-not $t){continue}; $t=($t -replace '\s+',' ').Trim(); if($t.Length -gt 200){$t=$t.Substring(0,200)+'…'}
    Write-Host ("[{0}] " -f $role) -NoNewline -ForegroundColor $(if($role -eq 'user'){'Green'}else{'Cyan'}); Write-Host $t; $n++
  }
  [void][Console]::ReadKey($true)
}

# ハイライト行(タイトル行)だけを書き換える部分更新。矢印移動時の全画面再描画(ちらつき)を防ぐ。
# 各項目は3行(タイトル/メタ/区切り線)。ヘッダは6行なので r 番目のタイトル行は Y=6+r*3。
function Write-Title([int]$r,[int]$idx,[object[]]$files,[int]$sel,[int]$dw){
  if($idx -lt 0 -or $idx -ge $files.Count){ return }
  $info=Scan-Cached $files[$idx]
  $ttl=RowTitle $info $dw
  [Console]::SetCursorPosition(0,6+$r*3)
  if($idx -eq $sel){ Write-Host ("> "+$ttl) -NoNewline -ForegroundColor White -BackgroundColor DarkBlue }
  else { Write-Host ("  "+$ttl) -NoNewline -ForegroundColor Gray }
}

# 選択した会話を現在のフォルダへ取り込み(別OS/別フォルダの会話も再開可能にする)
function Import-Session($info){
  $here=(Get-Location).Path; $dest=Join-Path $projects (Encode $here)
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $dp=Join-Path $dest "$($info.sid).jsonl"
  if($info.file -ne $dp){ Copy-Item $info.file $dp -Force }
}
# サブエージェント行から実行元メイン会話の info を引く(見つからなければ $null)。
function Parent-Info($sub){
  $pf=@($allSessions | Where-Object { $_.BaseName -eq $sub.parentSid } | Select-Object -First 1)
  if($pf.Count){ return (Scan-Cached $pf[0]) }
  return $null
}
function Launch-Claude([string[]]$cargs){
  [Console]::CursorVisible=$true; Clear-Host
  $rc=(Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source
  if($rc){ & $rc @cargs } else { Write-Host ("実行してください: claude " + ($cargs -join ' ')) -ForegroundColor Yellow }
}
# 開こうとした会話が使用中(アクセス中)なら警告して中止($true=中止)。F で強行可。
function Block-IfInUse($info){
  $script:lockSids = Load-Locks   # 直前に最新化
  if(-not $script:lockSids.ContainsKey($info.sid)){ return $false }
  $m=$script:lockSids[$info.sid]; $isSelf=($m -eq $env:COMPUTERNAME)
  Clear-Host; Write-Host ''
  Write-Host '  ⚠ この会話は現在アクセス中(使用中)です' -ForegroundColor Red
  Write-Host '  ----------------------------------------' -ForegroundColor Red; Write-Host ''
  Write-Host ("  使用中のデバイス: {0}{1}" -f $m,$(if($isSelf){'（このデバイス）'})) -ForegroundColor Yellow
  Write-Host ("  会話: {0}" -f $info.title) -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  同時に開くと履歴が壊れる(.sync-conflict)恐れがあります。' -ForegroundColor Yellow
  if($isSelf){ Write-Host '  このデバイスの別ウィンドウ/タブで開いています。そちらを終了してから開き直してください。' -ForegroundColor Yellow }
  else { Write-Host '  先にそのデバイス側でこの会話を終了(切断)してから、開き直してください。' -ForegroundColor Yellow }
  Write-Host ''
  Write-Host '  任意キーで戻る    /    F = それでも開く(危険)' -ForegroundColor DarkGray
  $k=[Console]::ReadKey($true)
  if("$($k.KeyChar)" -match '^[fF]$'){ return $false }   # 強行
  return $true                                            # 中止
}
# 「文脈を引き継いで新規」用に、会話の文脈(最初の要望 + 直近のやり取り)を組み立てる
function Build-Context($file){
  $firstU=@(); $tail=@()
  foreach($line in [System.IO.File]::ReadLines($file)){
    if(-not ($line.Contains('"role":"user"') -or $line.Contains('"role":"assistant"'))){ continue }
    try{ $o=$line|ConvertFrom-Json }catch{ continue }
    $role=$o.message.role; if($role -ne 'user' -and $role -ne 'assistant'){ continue }
    $t=MsgText $o; if(-not $t){ continue }; $t=($t -replace '\s+',' ').Trim(); if(-not $t){ continue }
    if($t.Length -gt 500){ $t=$t.Substring(0,500) }
    if($role -eq 'user' -and $firstU.Count -lt 3){ $firstU+=("- "+$t) }
    $tail+=(("{0}: " -f $role)+$t); if($tail.Count -gt 12){ $tail=@($tail[1..($tail.Count-1)]) }
  }
  $parts=@('以下は引き継ぎ元の会話の文脈です。これを踏まえてユーザーを支援してください。')
  if($firstU.Count){ $parts+=''; $parts+='## 最初の要望'; $parts+=$firstU }
  $parts+=''; $parts+='## 直近のやり取り'; $parts+=$tail
  $ctx=($parts -join "`n"); if($ctx.Length -gt 6000){ $ctx=$ctx.Substring(0,6000) }
  $ctx
}
# 起動権限を選ぶピッカー(戻り値: 権限文字列 / 取消は $null)。上位権限は警告再確認。
function Pick-Permission {
  $opts=@(
    @{v='default'; l='既定(都度確認)'}, @{v='plan'; l='プラン(読取中心・安全)'}, @{v='acceptEdits'; l='編集を自動承認'},
    @{v='auto'; l='自動(オート)'}, @{v='dontAsk'; l='確認しない'},
    @{v='bypassPermissions'; l='⚠ 権限バイパス'}, @{v='full'; l='⚠⚠ 完全フリー(全回避・env取得/コピー可)'}
  )
  $sel=0; $lastW=[Console]::WindowWidth
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  この起動で使う権限を選ぶ' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    for($i=0;$i -lt $opts.Count;$i++){ $line=$(if($i -eq $sel){' > '}else{'   '})+$opts[$i].l; if($i -eq $sel){ Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line } }
    Write-Host ''; Write-Host '  Up/Down 選ぶ   Enter 決定   Esc 戻る' -ForegroundColor DarkGray
    while(-not [Console]::KeyAvailable){ Start-Sleep -Milliseconds 80; if([Console]::WindowWidth -ne $lastW){ $lastW=[Console]::WindowWidth; break } }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'UpArrow'   { if($sel -gt 0){$sel--} }
      'DownArrow' { if($sel -lt $opts.Count-1){$sel++} }
      'Escape'    { return $null }
      'Enter'     {
        $v=$opts[$sel].v
        if($v -eq 'bypassPermissions' -or $v -eq 'full'){
          Clear-Host; Write-Host ''; Write-Host '  ⚠ 上位権限の確認' -ForegroundColor Red
          if($v -eq 'full'){ Write-Host '  完全フリーは全ての権限チェックを回避し、env(秘密)値の取得・コピー・任意コマンド実行まで無確認で許可します。' -ForegroundColor Yellow }
          else { Write-Host '  権限バイパスは権限プロンプトを出さずにツールを実行します。' -ForegroundColor Yellow }
          Write-Host ''; Write-Host '  本当にこの権限で起動しますか? [y/N]' -ForegroundColor Red
          $a=[Console]::ReadKey($true); if("$($a.KeyChar)" -match '^[yY]$'){ return $v } else { continue }
        }
        return $v
      }
    }
  }
}
function Perm-Args([string]$perm){ switch("$perm"){ 'full'{,@('--dangerously-skip-permissions')} 'plan'{,@('--permission-mode','plan')} 'acceptEdits'{,@('--permission-mode','acceptEdits')} 'auto'{,@('--permission-mode','auto')} 'dontAsk'{,@('--permission-mode','dontAsk')} 'bypassPermissions'{,@('--permission-mode','bypassPermissions')} default{,@()} } }
# 再開時に前回の モデル/思考深度/権限 を引き継ぐ: launchopts.map(起動時にフックが記録) を読む
function Get-LaunchOpts([string]$sid){
  $r=@{ model=''; effort=''; perm='' }
  $files=@(); if($cfg.share){ $files+=(Join-Path $cfg.share 'sessions\launchopts.map') }; $files+=(Join-Path $claude 'sessions\launchopts.map')
  foreach($f in $files){ if($f -and (Test-Path $f)){ foreach($l in (Get-Content $f -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if($a[0] -eq $sid){ if($a.Count -ge 2 -and $a[1]){ $r.model=$a[1] }; if($a.Count -ge 3 -and $a[2]){ $r.effort=$a[2] }; if($a.Count -ge 4 -and $a[3]){ $r.perm=$a[3] }; return $r } } } }
  $r
}
# launchopts に無い場合の保険: 会話履歴から最後に使われたモデルを拾う
function Get-TranscriptModel([string]$file){
  $m=''
  try{ foreach($line in (Get-Content $file -Tail 400 -Encoding utf8 -EA SilentlyContinue)){ if($line -match '"model"\s*:\s*"(claude[^"]*)"'){ $m=$matches[1] } } }catch{}
  $m
}
# 再開時に付与する引数(model/effort/permission)を組み立て、フック記録用 env も設定。permOverride で権限上書き。
function Inherit-Args($info,[string]$permOverride){
  $o=Get-LaunchOpts $info.sid
  $model= if($o.model){$o.model} else { Get-TranscriptModel $info.file }
  $effort=$o.effort
  $perm= if($permOverride){$permOverride} else { $o.perm }
  $a=@(); if($model){ $a+=@('--model',$model) }; if($effort){ $a+=@('--effort',$effort) }; $a+=(Perm-Args $perm)
  $env:CSS_LAUNCH_MODEL=$model; $env:CSS_LAUNCH_EFFORT=$effort; $env:CSS_LAUNCH_PERM=$perm
  ,$a
}

# 選択項目の操作メニュー。戻り値: resume / fork / newctx / fav / preview / perm / back
function Action-Menu($info){
  Clear-Host
  $favTxt= if($favs.ContainsKey($info.sid)){'から外す'}else{'に追加'}
  Write-Host ("操作: "+$info.title) -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  [Enter] 続きから (このフォルダで再開)" -ForegroundColor Gray
  Write-Host ("  [f]     ★ お気に入り"+$favTxt) -ForegroundColor Yellow
  Write-Host "  [k]     フォーク (複製して別の分岐で続ける・元は変更しない)" -ForegroundColor Gray
  Write-Host "  [n]     文脈を引き継いで新しい会話を始める" -ForegroundColor Gray
  Write-Host "  [r]     権限を変えて再開 (plan〜完全フリー)" -ForegroundColor Gray
  Write-Host "  [p]     内容プレビュー" -ForegroundColor Gray
  Write-Host "  [Esc]   戻る" -ForegroundColor DarkGray
  while($true){
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'Enter'    { return 'resume' }
      'Escape'   { return 'back' }
      'Spacebar' { return 'preview' }
      default {
        switch -CaseSensitive ([string]$k.KeyChar){
          'f' { return 'fav' } 'F' { return 'fav' }
          'k' { return 'fork' } 'K' { return 'fork' }
          'n' { return 'newctx' } 'N' { return 'newctx' }
          'r' { return 'perm' } 'R' { return 'perm' }
          'p' { return 'preview' } 'P' { return 'preview' }
        }
      }
    }
  }
}
# サブエージェント行の操作メニュー(戻り値: openparent / preview / back)。サブ自体は再開単位ではないので親を開く。
function SubMenu($info){
  Clear-Host
  $pt= if($titleMap.ContainsKey($info.parentSid) -and $titleMap[$info.parentSid]){ $titleMap[$info.parentSid] } else { $info.parentSid }
  $isRun=(((Get-Date)-$info.time).TotalSeconds -le $script:subWin)
  Write-Host ("サブエージェント: "+$info.title) -ForegroundColor Cyan
  Write-Host ("  種別: {0}    実行元デバイス: {1}" -f $info.agentType,$info.device) -ForegroundColor DarkGray
  Write-Host ("  実行元メイン: {0}{1}" -f $pt,$(if($isRun){'  ← 現在このメインから実行中'}else{''})) -ForegroundColor $(if($isRun){'Yellow'}else{'DarkGray'})
  Write-Host ""
  Write-Host "  [Enter] 実行元のメイン会話を開く" -ForegroundColor Gray
  Write-Host "  [p]     内容プレビュー" -ForegroundColor Gray
  Write-Host "  [Esc]   戻る" -ForegroundColor DarkGray
  while($true){
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'Enter'    { return 'openparent' }
      'Escape'   { return 'back' }
      'Spacebar' { return 'preview' }
      default { switch -CaseSensitive ([string]$k.KeyChar){ 'p'{return 'preview'} 'P'{return 'preview'} } }
    }
  }
}
# ページ番号ジャンプの入力(戻り値: 1..pages / 取消は $null)。Ctrl+G で開く。
function Pick-Page([int]$pages){
  if($pages -le 1){ return $null }
  $buf=''
  while($true){
    Clear-Host; Write-Host ''; Write-Host '  ページ番号へジャンプ' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor Cyan; Write-Host ''
    Write-Host ("  ページ番号 (1-$pages): $buf" + [char]0x2588) -ForegroundColor White
    Write-Host ''; Write-Host '  数字=入力   Backspace=消去   Enter=決定   Esc=取消' -ForegroundColor DarkGray
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'Enter'     { if($buf){ $n=[int]$buf; if($n -ge 1 -and $n -le $pages){ return $n } else { $buf='' } } }
      'Escape'    { return $null }
      'Backspace' { if($buf.Length){ $buf=$buf.Substring(0,$buf.Length-1) } }
      default     { $ch="$($k.KeyChar)"; if($ch -match '^[0-9]$' -and $buf.Length -lt 6){ $buf+=$ch } }
    }
  }
}

# ===== 対話ループ =====
$rows=ItemsPerPage
$ti=0; $sel=0; $pageTop=0; $search=''
$files=@(Tab-Files $ti $search)
[Console]::CursorVisible=$false
$needFull=$true; $shownSel=-1; $lastW=[Console]::WindowWidth; $lastH=[Console]::WindowHeight
$nextLockCheck=(Get-Date).AddSeconds(3)
$nextSubCheck=(Get-Date).AddSeconds(5)
try {
  while($true){
    $rows=ItemsPerPage
    $pages=[Math]::Max(1,[Math]::Ceiling($files.Count/$rows))
    if($sel -ge $files.Count){ $sel=[Math]::Max(0,$files.Count-1) }; if($sel -lt 0){$sel=0}
    $oldTop=$pageTop
    if($sel -lt $pageTop){ $pageTop=$sel }
    if($sel -ge $pageTop+$rows){ $pageTop=$sel-$rows+1 }
    if($pageTop -lt 0){$pageTop=0}
    if($pageTop -ne $oldTop){ $needFull=$true }
    # 文脈変化($needFull=タブ/検索/ページ/リサイズ/サブ画面復帰)はフル描画。選択移動は2行だけ軽量更新(重くない・ちらつかない)。
    if($needFull){
      $script:fullClear=$true
      Draw $ti $files $sel $pageTop $rows $search
      $shownSel=$sel; $needFull=$false
    } elseif($sel -ne $shownSel){
      $w=[Console]::WindowWidth; if($w -lt 44){$w=80}; $script:scrW=$w; $dw=[Math]::Min($w-2,78)
      Paint-Title ($shownSel-$pageTop) $shownSel $files $sel $dw   # 旧選択行 → 通常表示へ
      Paint-Title ($sel-$pageTop) $sel $files $sel $dw             # 新選択行 → ハイライト
      $shownSel=$sel
    }
    # キー待ち(ノンブロッキング)。リサイズ/フォーカス復帰、および「アクセス中」状態の変化を検知して自動再描画。
    while(-not [Console]::KeyAvailable){
      Start-Sleep -Milliseconds 80
      $cw=[Console]::WindowWidth; $chh=[Console]::WindowHeight
      if($cw -ne $lastW -or $chh -ne $lastH){ $lastW=$cw; $lastH=$chh; $needFull=$true; break }
      if((Get-Date) -ge $nextLockCheck){
        $nextLockCheck=(Get-Date).AddSeconds(3)
        $nl=Load-Locks; $ns=Locks-Sig $nl
        if($ns -ne $script:lockSig){ $script:lockSids=$nl; $script:lockSig=$ns; $needFull=$true; break }   # 使用中の変化をライブ反映
      }
      if((Get-Date) -ge $nextSubCheck){
        $nextSubCheck=(Get-Date).AddSeconds(5)
        $nr=Load-RunSubs; $nrs=RunSubs-Sig $nr
        if($nrs -ne $script:runSig){ $script:runSubs=$nr; $script:runSig=$nrs; $needFull=$true; break }   # サブエージェント実行中の変化をライブ反映
      }
    }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true)
    # Ctrl+G: ページ番号ジャンプ(プレーンな g/G は検索へ流す)
    if($k.Key -eq 'G' -and ($k.Modifiers -band [System.ConsoleModifiers]::Control)){
      $pg=Pick-Page $pages
      if($pg){ $pageTop=($pg-1)*$rows; $sel=$pageTop }
      $needFull=$true; continue
    }
    switch($k.Key){
      'UpArrow'    { $sel-- }
      'DownArrow'  { $sel++ }
      'LeftArrow'  { $ti=($ti-1+$tabs.Count)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search); $needFull=$true }
      'RightArrow' { $ti=($ti+1)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search); $needFull=$true }
      'PageDown'   { $sel=[Math]::Min($files.Count-1,$pageTop+$rows); $pageTop=$sel; $needFull=$true }
      'PageUp'     { $pageTop=[Math]::Max(0,$pageTop-$rows); $sel=$pageTop; $needFull=$true }
      'Home'       { $sel=0;$pageTop=0; $needFull=$true }
      'End'        { $sel=$files.Count-1; $needFull=$true }
      'Spacebar'   { if($files.Count -gt 0){ Preview $files[$sel].FullName; $needFull=$true } }
      'Backspace'  { if($search.Length -gt 0){ $search=$search.Substring(0,$search.Length-1); $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search); $needFull=$true } }
      'Escape'     { if($search){ $search=''; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search); $needFull=$true } else { return } }
      'Enter'      {
        if($files.Count -gt 0){
          $info=Scan-Cached $files[$sel]
          if($info.isSub){
            $p=Parent-Info $info
            if($p){ if(Block-IfInUse $p){ $needFull=$true } else { Import-Session $p; Launch-Claude (@('--resume',$p.sid)+(Inherit-Args $p $null)); return } }
            else { Preview $info.file; $needFull=$true }   # 親が見つからなければ内容を表示
          } else {
            if(Block-IfInUse $info){ $needFull=$true } else { Import-Session $info; Launch-Claude (@('--resume',$info.sid)+(Inherit-Args $info $null)); return }
          }
        }
      }
      'Tab'        {
        if($files.Count -gt 0){
          $info=Scan-Cached $files[$sel]
          if($info.isSub){
            switch(SubMenu $info){
              'openparent'{ $p=Parent-Info $info; if($p){ if(Block-IfInUse $p){ $needFull=$true } else { Import-Session $p; Launch-Claude (@('--resume',$p.sid)+(Inherit-Args $p $null)); return } } else { Preview $info.file; $needFull=$true } }
              'preview'   { Preview $info.file; $needFull=$true }
              default     { $needFull=$true }
            }
          } else {
            switch(Action-Menu $info){
              'resume'  { if(Block-IfInUse $info){ $needFull=$true } else { Import-Session $info; Launch-Claude (@('--resume',$info.sid)+(Inherit-Args $info $null)); return } }
              'fork'    { if(Block-IfInUse $info){ $needFull=$true } else { Import-Session $info; Launch-Claude (@('--resume',$info.sid,'--fork-session')+(Inherit-Args $info $null)); return } }
              'newctx'  { $ctx=Build-Context $info.file; Launch-Claude @('--append-system-prompt',$ctx); return }
              'perm'    { $pv=Pick-Permission; if($null -ne $pv){ if(Block-IfInUse $info){ $needFull=$true } else { Import-Session $info; Launch-Claude (@('--resume',$info.sid)+(Inherit-Args $info $pv)); return } } else { $needFull=$true } }
              'fav'     { Toggle-Fav $info.sid; if($tabs[$ti].name -eq 'お気に入り'){ $files=@(Tab-Files $ti $search) }; $needFull=$true }
              'preview' { Preview $info.file; $needFull=$true }
              default   { $needFull=$true }
            }
          }
        }
      }
      default {
        $ch=$k.KeyChar
        if($ch -and ([int][char]$ch) -ge 32){ $search+=$ch; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search); $needFull=$true }
      }
    }
  }
} finally { [Console]::CursorVisible=$true }
