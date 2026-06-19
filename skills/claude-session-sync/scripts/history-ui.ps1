<#  claude-session-sync : 履歴ブラウザ UI (Windows)  —  `claude -h` から起動
    公式 `claude --resume` を踏襲。上部に枠付き検索ボックス(入力で即フィルタ)、その下にタブ
    ([このプロジェクト][全履歴][最近7日][★お気に入り])。各項目は 2行(タイトル / メタ)＋区切り線。
    操作: 文字入力で検索 / Backspace 消去 / Esc クリア(空なら終了) / ↑↓ 選択 / ←→ タブ /
          PageUp,PageDown ページ / Enter 再開 / Space 内容プレビュー /
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
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }
function Get-AllSessions {
  Get-ChildItem $projects -Recurse -Filter *.jsonl -EA SilentlyContinue | Where-Object {
    (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
    (Split-Path $_.DirectoryName -Leaf) -notlike '*session-sync-titlegen*' -and
    $_.BaseName -notlike 'agent-*' -and $_.BaseName -ne 'journal'
  } | Sort-Object LastWriteTime -Descending
}
function MsgText($o){ $c=$o.message.content; if($null -eq $c){return ''}; if($c -is [string]){return $c}; $p=@(); foreach($b in $c){ if($b.type -eq 'text' -and $b.text){ $p+=$b.text } }; ($p -join ' ') }
function DeviceFromCwd([string]$cwd){
  if(-not $cwd){ return 'unknown' }
  if($cwd -match '^[A-Za-z]:\\'){ $u=if($cwd -match '^[A-Za-z]:\\Users\\([^\\]+)'){$matches[1]}else{'?'}; return "Win/$u" }
  if($cwd -match '^/Users/([^/]+)'){ return "Mac/$($matches[1])" }
  if($cwd -match '^/home/([^/]+)'){ return "Linux/$($matches[1])" }
  if($cwd -match '^/root'){ return 'Linux/root' }
  return 'unknown'
}
function RelTime([datetime]$dt){
  $s=((Get-Date)-$dt).TotalSeconds
  if($s -lt 60){'たった今'} elseif($s -lt 3600){"$([int]($s/60))分前"} elseif($s -lt 86400){"$([int]($s/3600))時間前"}
  elseif($s -lt 2592000){"$([int]($s/86400))日前"} else {"$([int]($s/2592000))ヶ月前"}
}
function ProjShort([string]$dir){ $n=Split-Path $dir -Leaf; if($n.Length -gt 22){'…'+$n.Substring($n.Length-21)}else{$n} }
# 端末表示幅(全角CJK/絵文字=2桁)。枠線の桁ずれ防止に使用。
function CharW([int]$c){
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
$script:scanCache=@{}
function Scan-Cached($f){
  if($script:scanCache.ContainsKey($f.FullName)){ return $script:scanCache[$f.FullName] }
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
  $r=[pscustomobject]@{ sid=$sid; device=$dev; title=$ttl; msgs=$msgStr; file=$f.FullName; time=$f.LastWriteTime; proj=(ProjShort $f.DirectoryName) }
  $script:scanCache[$f.FullName]=$r; $r
}
$palette=@('Cyan','Green','Yellow','Magenta','Blue','Red','DarkCyan','DarkGreen','DarkYellow','DarkMagenta','White')
function ColorFor([string]$dev){ $h=0; foreach($ch in $dev.ToCharArray()){ $h=($h*31+[int]$ch) }; $palette[[Math]::Abs($h)%$palette.Count] }

$cwdKey=Encode((Get-Location).Path)
$tabs=@(
  @{ name='このプロジェクト'; sel={ param($f) (Split-Path $f.DirectoryName -Leaf) -eq $cwdKey } },
  @{ name='全履歴';           sel={ param($f) $true } },
  @{ name='最近7日';          sel={ param($f) $f.LastWriteTime -ge (Get-Date).AddDays(-7) } },
  @{ name='★お気に入り';      sel={ param($f) $favs.ContainsKey($f.BaseName) } }
)
$allSessions=@(Get-AllSessions)
function Tab-Files($ti,$search){
  $f=@($allSessions | Where-Object { & $tabs[$ti].sel $_ })
  if($search){ $f=@($f | Where-Object { (Split-Path $_.DirectoryName -Leaf) -match [regex]::Escape($search) -or $_.BaseName -like "$search*" -or ($script:scanCache.ContainsKey($_.FullName) -and $script:scanCache[$_.FullName].title -match [regex]::Escape($search)) }) }
  $f
}
function ItemsPerPage { [Math]::Max(2,[int][Math]::Floor(([Console]::WindowHeight-8)/3)) }

# お気に入りは ★ をタイトル前に付けて表示(描画と部分更新で共用)。
function RowTitle($info,$dw){
  $star= if($favs.ContainsKey($info.sid)){'★ '}else{''}
  $maxT=$dw-2-$star.Length; if($maxT -lt 4){ $maxT=4 }
  $ttl=$info.title; if($ttl.Length -gt $maxT){ $ttl=$ttl.Substring(0,$maxT-1)+'…' }
  $star+$ttl
}

# ---- 描画(枠付き検索 + タブ + 2行/区切り線) ----
function Draw([int]$ti,[object[]]$files,[int]$sel,[int]$pageTop,[int]$rows,[string]$search){
  $w=[Console]::WindowWidth; if($w -lt 44){$w=80}; $dw=[Math]::Min($w-2,78); $boxW=[Math]::Min($dw,56)
  Clear-Host
  # 検索ボックス(枠付き)
  $label='─ 🔍 検索 '
  Write-Host ("┌"+$label+('─'*[Math]::Max(0,$boxW-(DispWidth $label)))+"┐") -ForegroundColor DarkCyan
  $inner=$search+'█'; $pad=[Math]::Max(0,$boxW-1-(DispWidth $inner))
  Write-Host ("│ ") -NoNewline -ForegroundColor DarkCyan
  Write-Host ($inner) -NoNewline -ForegroundColor White
  Write-Host ((' '*$pad)+"│") -ForegroundColor DarkCyan
  Write-Host ("└"+('─'*$boxW)+"┘") -ForegroundColor DarkCyan
  # タブ
  for($i=0;$i -lt $tabs.Count;$i++){
    if($i -eq $ti){ Write-Host " $($tabs[$i].name) " -NoNewline -ForegroundColor Black -BackgroundColor Cyan }
    else { Write-Host " $($tabs[$i].name) " -NoNewline -ForegroundColor DarkGray }
    Write-Host '  ' -NoNewline
  }
  Write-Host ''
  $total=$files.Count; $page=[Math]::Floor($pageTop/$rows)+1; $pages=[Math]::Max(1,[Math]::Ceiling($total/$rows))
  Write-Host ("Enter で続きから   ページ $page/$pages ・ 全 $total 件") -ForegroundColor DarkGray
  Write-Host (' '+('─'*$dw)) -ForegroundColor DarkGray
  for($r=0;$r -lt $rows;$r++){
    $idx=$pageTop+$r
    if($idx -ge $total){ break }
    $info=Scan-Cached $files[$idx]
    $ttl=RowTitle $info $dw
    if($idx -eq $sel){ Write-Host ("❯ "+$ttl) -ForegroundColor White -BackgroundColor DarkBlue }
    else { Write-Host ("  "+$ttl) -ForegroundColor Gray }
    Write-Host "   " -NoNewline
    Write-Host $info.device -NoNewline -ForegroundColor (ColorFor $info.device)
    Write-Host (" │ {0} msg │ {1} │ {2}" -f $info.msgs,(RelTime $info.time),$info.proj) -ForegroundColor DarkGray
    Write-Host (' '+('─'*$dw)) -ForegroundColor DarkGray
  }
  Write-Host "文字=検索  ↑↓=選択  ←→=タブ  Enter=再開  Tab=操作(★/フォーク/引継ぎ)  Space=内容  Esc=終了" -ForegroundColor DarkGray
}

if($SelfTest){
  $files=@(Tab-Files 1 'syncthing'); if($files.Count -eq 0){ $files=@(Tab-Files 1 '') }
  $n=[Math]::Min(2,$files.Count); $sb=New-Object System.Text.StringBuilder
  $boxW=56; $label='─ 🔍 検索 '; $inner='syncthing█'
  [void]$sb.AppendLine("┌"+$label+('─'*[Math]::Max(0,$boxW-(DispWidth $label)))+"┐")
  [void]$sb.AppendLine("│ "+$inner+(' '*[Math]::Max(0,$boxW-1-(DispWidth $inner)))+"│")
  [void]$sb.AppendLine("└"+('─'*$boxW)+"┘")
  [void]$sb.AppendLine(" このプロジェクト    [全履歴]    最近7日    ★お気に入り")
  [void]$sb.AppendLine(' '+('─'*54))
  for($r=0;$r -lt $n;$r++){ $info=Scan-Cached $files[$r]
    [void]$sb.AppendLine($(if($r -eq 0){'❯ '}else{'  '})+$info.title)
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
  if($idx -eq $sel){ Write-Host ("❯ "+$ttl) -NoNewline -ForegroundColor White -BackgroundColor DarkBlue }
  else { Write-Host ("  "+$ttl) -NoNewline -ForegroundColor Gray }
}

# 選択した会話を現在のフォルダへ取り込み(別OS/別フォルダの会話も再開可能にする)
function Import-Session($info){
  $here=(Get-Location).Path; $dest=Join-Path $projects (Encode $here)
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $dp=Join-Path $dest "$($info.sid).jsonl"
  if($info.file -ne $dp){ Copy-Item $info.file $dp -Force }
}
function Launch-Claude([string[]]$cargs){
  [Console]::CursorVisible=$true; Clear-Host
  $rc=(Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source
  if($rc){ & $rc @cargs } else { Write-Host ("実行してください: claude " + ($cargs -join ' ')) -ForegroundColor Yellow }
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
# 選択項目の操作メニュー。戻り値: resume / fork / newctx / fav / preview / back
function Action-Menu($info){
  Clear-Host
  $favTxt= if($favs.ContainsKey($info.sid)){'から外す'}else{'に追加'}
  Write-Host ("操作: "+$info.title) -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  [Enter] 続きから (このフォルダで再開)" -ForegroundColor Gray
  Write-Host ("  [f]     ★ お気に入り"+$favTxt) -ForegroundColor Yellow
  Write-Host "  [k]     フォーク (複製して別の分岐で続ける・元は変更しない)" -ForegroundColor Gray
  Write-Host "  [n]     文脈を引き継いで新しい会話を始める" -ForegroundColor Gray
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
          'p' { return 'preview' } 'P' { return 'preview' }
        }
      }
    }
  }
}

# ===== 対話ループ =====
$rows=ItemsPerPage
$ti=0; $sel=0; $pageTop=0; $search=''
$files=@(Tab-Files $ti $search)
[Console]::CursorVisible=$false
$needFull=$true; $shownSel=-1; $lastW=[Console]::WindowWidth; $lastH=[Console]::WindowHeight
try {
  while($true){
    $rows=ItemsPerPage
    if($sel -ge $files.Count){ $sel=[Math]::Max(0,$files.Count-1) }; if($sel -lt 0){$sel=0}
    $oldTop=$pageTop
    if($sel -lt $pageTop){ $pageTop=$sel }
    if($sel -ge $pageTop+$rows){ $pageTop=$sel-$rows+1 }
    if($pageTop -lt 0){$pageTop=0}
    if($pageTop -ne $oldTop){ $needFull=$true }
    if($needFull){
      Draw $ti $files $sel $pageTop $rows $search
      $shownSel=$sel; $needFull=$false
    } elseif($sel -ne $shownSel){
      # ハイライトのみ移動: 旧選択行と新選択行のタイトル行だけ書き換え(画面消去しない)
      try {
        $w=[Console]::WindowWidth; if($w -lt 44){$w=80}; $dw=[Math]::Min($w-2,78)
        Write-Title ($shownSel-$pageTop) $shownSel $files $sel $dw
        Write-Title ($sel-$pageTop) $sel $files $sel $dw
        $shownSel=$sel
      } catch { $needFull=$true; continue }
    }
    # キー待ち(ノンブロッキング)。ウィンドウのリサイズ/フォーカス復帰で崩れたら自動で全再描画。
    while(-not [Console]::KeyAvailable){
      Start-Sleep -Milliseconds 80
      $cw=[Console]::WindowWidth; $chh=[Console]::WindowHeight
      if($cw -ne $lastW -or $chh -ne $lastH){ $lastW=$cw; $lastH=$chh; $needFull=$true; break }
    }
    if(-not [Console]::KeyAvailable){ continue }
    $k=[Console]::ReadKey($true)
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
          $info=Scan-Cached $files[$sel]; Import-Session $info; Launch-Claude @('--resume',$info.sid); return
        }
      }
      'Tab'        {
        if($files.Count -gt 0){
          $info=Scan-Cached $files[$sel]
          switch(Action-Menu $info){
            'resume'  { Import-Session $info; Launch-Claude @('--resume',$info.sid); return }
            'fork'    { Import-Session $info; Launch-Claude @('--resume',$info.sid,'--fork-session'); return }
            'newctx'  { $ctx=Build-Context $info.file; Launch-Claude @('--append-system-prompt',$ctx); return }
            'fav'     { Toggle-Fav $info.sid; if($ti -eq 3){ $files=@(Tab-Files $ti $search) }; $needFull=$true }
            'preview' { Preview $info.file; $needFull=$true }
            default   { $needFull=$true }
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
