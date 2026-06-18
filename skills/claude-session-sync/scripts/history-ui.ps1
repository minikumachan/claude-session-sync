<#  claude-session-sync : 履歴ブラウザ UI (Windows)  —  `claude -h` から起動
    公式 `claude --resume` のUIを参考に、タブ式・ページ式・遅延読込の対話UI。
    タブ: [このプロジェクト(=公式-rと同じパス依存)] [全履歴(全デバイス)] [最近7日]
    操作: ↑↓=選択 / ←→=タブ切替 / PageUp,PageDown=ページ / Enter=再開 / / =検索 / q,Esc=終了
          マウスホイール=スクロール(Windowsのみ・対応端末)
    遅延読込: 表示中の行だけ内容(タイトル/デバイス)を読む。ページ送りで先を読み込む。
    -SelfTest を付けると非対話で1フレーム描画してテキストを返す(検証用)。  #>
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
$claude   = Join-Path $env:USERPROFILE '.claude'
$projects = Join-Path $claude 'projects'
if(-not (Test-Path $projects)){ Write-Host "履歴フォルダがありません: $projects" -ForegroundColor Yellow; return }
$cfgPath = Join-Path $claude 'session-sync.local.conf'
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
$script:scanCache=@{}
function Scan-Cached($f){
  if($script:scanCache.ContainsKey($f.FullName)){ return $script:scanCache[$f.FullName] }
  $cwd='';$prev='';$ai=''
  foreach($line in (Get-Content $f.FullName -Encoding utf8 -EA SilentlyContinue | Select-Object -First 120)){
    if(-not $line.Trim()){continue}; try{$o=$line|ConvertFrom-Json}catch{continue}
    if(-not $cwd -and $o.cwd){ $cwd=[string]$o.cwd }
    if(-not $ai -and $o.type -eq 'ai-title' -and $o.aiTitle){ $ai=[string]$o.aiTitle }
    if(-not $prev -and $o.message.role -eq 'user'){ $t=MsgText $o; if($t){ $prev=($t -replace '\s+',' ').Trim() } }
    if($cwd -and $prev -and $ai){ break }
  }
  $sid=$f.BaseName
  $dev= if($devMap.ContainsKey($sid)){$devMap[$sid]}else{ DeviceFromCwd $cwd }
  $ttl= if($titleMap.ContainsKey($sid)){$titleMap[$sid]}elseif($ai){$ai}elseif($prev){$prev}else{'(無題)'}
  $r=[pscustomobject]@{ sid=$sid; device=$dev; title=$ttl; file=$f.FullName }
  $script:scanCache[$f.FullName]=$r; $r
}
$palette=@('Cyan','Green','Yellow','Magenta','Blue','Red','DarkCyan','DarkGreen','DarkYellow','DarkMagenta','White')
function ColorFor([string]$dev){ $h=0; foreach($ch in $dev.ToCharArray()){ $h=($h*31+[int]$ch) }; $palette[[Math]::Abs($h)%$palette.Count] }

$cwdKey = Encode((Get-Location).Path)
$tabs = @(
  @{ name='このプロジェクト'; sel={ param($f) (Split-Path $f.DirectoryName -Leaf) -eq $cwdKey } },
  @{ name='全履歴';           sel={ param($f) $true } },
  @{ name='最近7日';          sel={ param($f) $f.LastWriteTime -ge (Get-Date).AddDays(-7) } }
)
$allSessions = @(Get-AllSessions)
function Tab-Files($ti,$search){
  $f = @($allSessions | Where-Object { & $tabs[$ti].sel $_ })
  if($search){ $f = @($f | Where-Object { (Split-Path $_.DirectoryName -Leaf) -match [regex]::Escape($search) -or $_.BaseName -like "$search*" -or ($script:scanCache.ContainsKey($_.FullName) -and $script:scanCache[$_.FullName].title -match [regex]::Escape($search)) }) }
  $f
}

function Render([int]$ti,[object[]]$files,[int]$sel,[int]$pageTop,[int]$rows,[string]$search){
  $out = New-Object System.Text.StringBuilder
  # タブ行
  $tabline=''
  for($i=0;$i -lt $tabs.Count;$i++){ $tabline += $(if($i -eq $ti){"[ $($tabs[$i].name) ]"}else{"  $($tabs[$i].name)  "}) }
  [void]$out.AppendLine($tabline)
  $total=$files.Count; $page=[Math]::Floor($pageTop/$rows)+1; $pages=[Math]::Max(1,[Math]::Ceiling($total/$rows))
  [void]$out.AppendLine("ページ $page/$pages  全 $total 件$(if($search){"  検索: $search"})   (↑↓選択 ←→タブ PgUp/PgDn頁 Enter再開 /検索 q終了)")
  for($r=0;$r -lt $rows;$r++){
    $idx=$pageTop+$r
    if($idx -ge $total){ [void]$out.AppendLine(''); continue }
    $info=Scan-Cached $files[$idx]
    $mark= if($idx -eq $sel){'>'}else{' '}
    $up=$files[$idx].LastWriteTime.ToString('MM-dd HH:mm')
    $ttl= if($info.title.Length -gt 56){ $info.title.Substring(0,55)+'…' }else{ $info.title }
    [void]$out.AppendLine(("{0} {1,4} {2}  {3,-12}  {4}" -f $mark,($idx+1),$up,$info.device,$ttl))
  }
  $out.ToString()
}

if($SelfTest){
  $files=@(Tab-Files 1 '')
  $rows=[Math]::Min(8,[Math]::Max(1,$files.Count))
  Render 1 $files 0 0 $rows '' | Write-Output
  return
}

# ===== 対話ループ =====
$rows = [Math]::Max(3, [Console]::WindowHeight - 5)
$ti=0; $sel=0; $pageTop=0; $search=''
$files=@(Tab-Files $ti $search)
function Clamp { $script:total=$files.Count; if($sel -ge $total){$script:sel=[Math]::Max(0,$total-1)}; if($sel -lt 0){$script:sel=0}
  if($sel -lt $pageTop){ $script:pageTop=$sel }
  if($sel -ge $pageTop+$rows){ $script:pageTop=$sel-$rows+1 }
  if($pageTop -lt 0){$script:pageTop=0} }

[Console]::CursorVisible=$false
try {
  while($true){
    Clamp
    Clear-Host
    Write-Host (Render $ti $files $sel $pageTop $rows $search)
    $k=[Console]::ReadKey($true)
    switch($k.Key){
      'UpArrow'    { $sel-- }
      'DownArrow'  { $sel++ }
      'LeftArrow'  { $ti=($ti-1+$tabs.Count)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      'RightArrow' { $ti=($ti+1)%$tabs.Count; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      'PageDown'   { $sel=[Math]::Min($files.Count-1,$pageTop+$rows) ; $pageTop=$sel }
      'PageUp'     { $pageTop=[Math]::Max(0,$pageTop-$rows); $sel=$pageTop }
      'Home'       { $sel=0;$pageTop=0 }
      'End'        { $sel=$files.Count-1 }
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
      'Oem2'       { # '/'
        [Console]::CursorVisible=$true; Write-Host "`n検索語(空でクリア): " -NoNewline; $search=[Console]::ReadLine(); [Console]::CursorVisible=$false
        $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search)
      }
      default {
        if($k.KeyChar -eq '/'){ [Console]::CursorVisible=$true; Write-Host "`n検索語(空でクリア): " -NoNewline; $search=[Console]::ReadLine(); [Console]::CursorVisible=$false; $sel=0;$pageTop=0; $files=@(Tab-Files $ti $search) }
      }
    }
  }
} finally {
  [Console]::CursorVisible=$true
}
