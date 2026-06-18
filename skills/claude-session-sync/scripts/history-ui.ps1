<#  claude-session-sync : 履歴ブラウザ UI (Windows)  —  `claude -h` から起動
    公式 `claude --resume` のピッカー(ヘッダ＋❯選択＋[要約][相対時刻][件数]列＋下部キーヒント)を
    踏襲しつつ、タブ([このプロジェクト][全履歴][最近7日])と「由来デバイス」列を追加。
    操作: ↑↓ 選択 / ←→ タブ / PageUp,PageDown ページ / Enter 再開 / Space 内容プレビュー / / 検索 / q,Esc 終了
    遅延読込: 表示中の行だけ内容を読む(ページ送りで先を読む)。  -SelfTest で1フレームをテキスト出力(検証用)。  #>
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
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }
function Get-AllSessions {
  Get-ChildItem $projects -Recurse -Filter *.jsonl -EA SilentlyContinue | Where-Object {
    (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
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
$script:scanCache=@{}
function Scan-Cached($f){
  if($script:scanCache.ContainsKey($f.FullName)){ return $script:scanCache[$f.FullName] }
  $cwd='';$prev='';$ai='';$msgs=0
  foreach($line in (Get-Content $f.FullName -Encoding utf8 -EA SilentlyContinue)){
    if(-not $line){continue}
    if($line -match '"type":"(user|assistant)"'){ $msgs++ }
    if($cwd -and $ai -and $prev){ continue }
    try{$o=$line|ConvertFrom-Json}catch{continue}
    if(-not $cwd -and $o.cwd){ $cwd=[string]$o.cwd }
    if(-not $ai -and $o.type -eq 'ai-title' -and $o.aiTitle){ $ai=[string]$o.aiTitle }
    if(-not $prev -and $o.message.role -eq 'user'){ $t=MsgText $o; if($t){ $prev=($t -replace '\s+',' ').Trim() } }
  }
  $sid=$f.BaseName
  $dev= if($devMap.ContainsKey($sid)){$devMap[$sid]}else{ DeviceFromCwd $cwd }
  $ttl= if($titleMap.ContainsKey($sid)){$titleMap[$sid]}elseif($ai){$ai}elseif($prev){$prev}else{'(無題)'}
  $r=[pscustomobject]@{ sid=$sid; device=$dev; title=$ttl; msgs=$msgs; file=$f.FullName; time=$f.LastWriteTime }
  $script:scanCache[$f.FullName]=$r; $r
}
$palette=@('Cyan','Green','Yellow','Magenta','Blue','Red','DarkCyan','DarkGreen','DarkYellow','DarkMagenta','White')
function ColorFor([string]$dev){ $h=0; foreach($ch in $dev.ToCharArray()){ $h=($h*31+[int]$ch) }; $palette[[Math]::Abs($h)%$palette.Count] }

$cwdKey=Encode((Get-Location).Path)
$tabs=@(
  @{ name='このプロジェクト'; sel={ param($f) (Split-Path $f.DirectoryName -Leaf) -eq $cwdKey } },
  @{ name='全履歴';           sel={ param($f) $true } },
  @{ name='最近7日';          sel={ param($f) $f.LastWriteTime -ge (Get-Date).AddDays(-7) } }
)
$allSessions=@(Get-AllSessions)
function Tab-Files($ti,$search){
  $f=@($allSessions | Where-Object { & $tabs[$ti].sel $_ })
  if($search){ $f=@($f | Where-Object { (Split-Path $_.DirectoryName -Leaf) -match [regex]::Escape($search) -or $_.BaseName -like "$search*" -or ($script:scanCache.ContainsKey($_.FullName) -and $script:scanCache[$_.FullName].title -match [regex]::Escape($search)) }) }
  $f
}

# ---- 描画(対話・色付き) ----
function Draw([int]$ti,[object[]]$files,[int]$sel,[int]$pageTop,[int]$rows,[string]$search){
  $w=[Console]::WindowWidth; if($w -lt 40){$w=80}
  Clear-Host
  # タブバー
  for($i=0;$i -lt $tabs.Count;$i++){
    if($i -eq $ti){ Write-Host "  $($tabs[$i].name)  " -NoNewline -ForegroundColor Black -BackgroundColor Cyan }
    else { Write-Host "  $($tabs[$i].name)  " -NoNewline -ForegroundColor DarkGray }
    Write-Host ' ' -NoNewline
  }
  Write-Host ''
  Write-Host ('─'*[Math]::Min($w-1,80)) -ForegroundColor DarkGray
  $total=$files.Count; $page=[Math]::Floor($pageTop/$rows)+1; $pages=[Math]::Max(1,[Math]::Ceiling($total/$rows))
  Write-Host ("  履歴を選んで Enter で続きから   ページ $page/$pages ・ 全 $total 件$(if($search){" ・ 検索『$search』"})") -ForegroundColor DarkGray
  for($r=0;$r -lt $rows;$r++){
    $idx=$pageTop+$r
    if($idx -ge $total){ Write-Host ''; continue }
    $info=Scan-Cached $files[$idx]
    $rel=(RelTime $info.time).PadLeft(7)
    $titleW=[Math]::Max(20,$w-40)
    $ttl=$info.title; if($ttl.Length -gt $titleW){ $ttl=$ttl.Substring(0,$titleW-1)+'…' } else { $ttl=$ttl.PadRight($titleW) }
    $meta=("{0}  {1,4}msg  " -f $rel,$info.msgs)
    if($idx -eq $sel){
      Write-Host ("❯ "+$ttl+"  ") -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
      Write-Host ($meta) -NoNewline -ForegroundColor Gray -BackgroundColor DarkBlue
      Write-Host ($info.device) -ForegroundColor White -BackgroundColor DarkBlue
    } else {
      Write-Host ("  "+$ttl+"  ") -NoNewline
      Write-Host ($meta) -NoNewline -ForegroundColor DarkGray
      Write-Host ($info.device) -ForegroundColor (ColorFor $info.device)
    }
  }
  Write-Host ('─'*[Math]::Min($w-1,80)) -ForegroundColor DarkGray
  Write-Host "  ↑↓ 選択   ←→ タブ   PgUp/PgDn ページ   Enter 再開   Space 内容   / 検索   q 終了" -ForegroundColor DarkGray
}

if($SelfTest){
  $files=@(Tab-Files 1 ''); $rows=[Math]::Min(6,[Math]::Max(1,$files.Count)); $sb=New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("TABS: "+(($tabs|ForEach-Object{$_.name}) -join ' | ')+"  (選択=全履歴)")
  for($r=0;$r -lt $rows;$r++){ $info=Scan-Cached $files[$r]; [void]$sb.AppendLine(("{0} {1,-7} {2,4}msg {3,-12} {4}" -f $(if($r -eq 0){'❯'}else{' '}),(RelTime $info.time),$info.msgs,$info.device,$info.title)) }
  $sb.ToString() | Write-Output; return
}

# ---- プレビュー ----
function Preview($file){
  Clear-Host
  Write-Host "── 内容プレビュー(任意キーで戻る)──" -ForegroundColor Cyan
  $n=0
  foreach($line in (Get-Content $file -Encoding utf8 -EA SilentlyContinue)){
    if($n -ge ([Console]::WindowHeight-3)){ Write-Host "  …(以降は Enter で開いてください)" -ForegroundColor DarkGray; break }
    if(-not $line.Trim()){continue}; try{$o=$line|ConvertFrom-Json}catch{continue}
    $role=$o.message.role; if($role -ne 'user' -and $role -ne 'assistant'){continue}
    $t=MsgText $o; if(-not $t){continue}
    $t=($t -replace '\s+',' ').Trim(); if($t.Length -gt 200){$t=$t.Substring(0,200)+'…'}
    Write-Host ("[{0}] " -f $role) -NoNewline -ForegroundColor $(if($role -eq 'user'){'Green'}else{'Cyan'}); Write-Host $t
    $n++
  }
  [void][Console]::ReadKey($true)
}

# ===== 対話ループ =====
$rows=[Math]::Max(3,[Console]::WindowHeight-6)
$ti=0; $sel=0; $pageTop=0; $search=''
$files=@(Tab-Files $ti $search)
[Console]::CursorVisible=$false
try {
  while($true){
    if($sel -ge $files.Count){ $sel=[Math]::Max(0,$files.Count-1) }; if($sel -lt 0){$sel=0}
    if($sel -lt $pageTop){ $pageTop=$sel }
    if($sel -ge $pageTop+$rows){ $pageTop=$sel-$rows+1 }
    if($pageTop -lt 0){$pageTop=0}
    Draw $ti $files $sel $pageTop $rows $search
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'UpArrow'    { $sel-- }
      'DownArrow'  { $sel++ }
      'LeftArrow'  { $ti=($ti-1+$tabs.Count)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      'RightArrow' { $ti=($ti+1)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      'PageDown'   { $sel=[Math]::Min($files.Count-1,$pageTop+$rows); $pageTop=$sel }
      'PageUp'     { $pageTop=[Math]::Max(0,$pageTop-$rows); $sel=$pageTop }
      'Home'       { $sel=0;$pageTop=0 }
      'End'        { $sel=$files.Count-1 }
      'Spacebar'   { if($files.Count -gt 0){ Preview $files[$sel].FullName } }
      'Enter'      {
        if($files.Count -gt 0){
          $info=Scan-Cached $files[$sel]
          $here=(Get-Location).Path; $dest=Join-Path $projects (Encode $here)
          New-Item -ItemType Directory -Force -Path $dest | Out-Null
          $dp=Join-Path $dest "$($info.sid).jsonl"
          if($info.file -ne $dp){ Copy-Item $info.file $dp -Force }
          [Console]::CursorVisible=$true; Clear-Host
          $rc=(Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source
          if($rc){ & $rc --resume $info.sid } else { Write-Host "再開: claude --resume $($info.sid)" }
          return
        }
      }
      'Q'          { return }
      'Escape'     { return }
      default {
        if($k.KeyChar -eq '/'){ [Console]::CursorVisible=$true; Write-Host "`n検索語(空でクリア): " -NoNewline; $search=[Console]::ReadLine(); [Console]::CursorVisible=$false; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      }
    }
  }
} finally { [Console]::CursorVisible=$true }
