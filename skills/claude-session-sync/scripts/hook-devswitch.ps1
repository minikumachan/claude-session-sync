<#  claude-session-sync : デバイス切替検知フック (Windows / SessionStart)
    会話が前回と異なるデバイスで開始/再開されたら、その旨と「このデバイスでの適切な作業パス」を
    stdout に出力して Claude の文脈へ伝える(SessionStart は stdout がそのまま文脈に入る)。
    sid -> device|cwd|time を <share>/sessions/lastseen.map に記録して切替を判定する。
    conf の deviceSwitchNotice=false で無効化。  #>
$ErrorActionPreference = 'SilentlyContinue'
if($env:CSS_TITLEGEN){ exit 0 }   # 自動タイトル生成中の claude -p は対象外
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ exit 0 }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
if($cfg.ContainsKey('deviceSwitchNotice') -and $cfg.deviceSwitchNotice -eq 'false'){ exit 0 }

# stdin(UTF-8) から session_id / cwd を取得
$sid=''; $cwd=(Get-Location).Path
try {
  $reader = New-Object System.IO.StreamReader([System.Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
  $raw = $reader.ReadToEnd(); $reader.Dispose()
  if($raw){ $j = $raw | ConvertFrom-Json; if($j.session_id){ $sid = $j.session_id }; if($j.cwd){ $cwd = $j.cwd } }
} catch {}
if(-not $sid){ exit 0 }

$dev = if($cfg.deviceName){ $cfg.deviceName } else { $env:COMPUTERNAME }
$mapDir = if($cfg.share){ Join-Path $cfg.share 'sessions' } else { Join-Path $claude 'sessions' }
New-Item -ItemType Directory -Force -Path $mapDir | Out-Null
$mapFile = Join-Path $mapDir 'lastseen.map'

# このデバイスでの「対応する作業パス」を推定(ホーム相対の同じ構造を探す)
function Translate-Path([string]$p){
  if(-not $p){ return $null }
  if(Test-Path $p){ return $p }                       # 既にローカルに在ればそのまま
  $rel=$null
  if($p -match '^[A-Za-z]:\\Users\\[^\\]+\\(.+)$'){ $rel = ($matches[1] -replace '\\','/') }
  elseif($p -match '^/Users/[^/]+/(.+)$'){ $rel = $matches[1] }
  elseif($p -match '^/home/[^/]+/(.+)$'){ $rel = $matches[1] }
  if(-not $rel){ return $null }
  $cand = Join-Path $env:USERPROFILE ($rel -replace '/','\')
  if(Test-Path $cand){ return $cand }
  return $null
}

# 前回エントリ(sid)を取得
$prevDev=''; $prevCwd=''
if(Test-Path $mapFile){
  foreach($l in (Get-Content $mapFile -Encoding utf8 -EA SilentlyContinue)){
    $a = $l -split "`t"; if($a.Count -ge 3 -and $a[0] -eq $sid){ $prevDev=$a[1]; $prevCwd=$a[2] }
  }
}

if($prevDev -and $prevDev -ne $dev){
  $sug = Translate-Path $prevCwd
  $msg = "[claude-session-sync] デバイス切替を検知しました。この会話は前回『$prevDev』(作業フォルダ: $prevCwd)で使われ、現在は『$dev』です。"
  if($sug){ $msg += " このデバイスでの対応する作業フォルダは『$sug』です。以降のファイル操作はこのデバイスのパスを使ってください(必要なら `cd `"$sug`")。" }
  else    { $msg += " 対応する作業フォルダを自動特定できませんでした(現在地: $cwd)。このデバイスの絶対パスで作業し、別デバイスのパス表記はそのまま使わないでください。" }
  Write-Output $msg
}

# 今回の状態で sid 行を更新(他行は維持)
$lines=@()
if(Test-Path $mapFile){ foreach($l in (Get-Content $mapFile -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if($a.Count -ge 1 -and $a[0] -ne $sid){ $lines+=$l } } }
$lines += ("{0}`t{1}`t{2}`t{3}" -f $sid,$dev,$cwd,(Get-Date -Format s))
try { [System.IO.File]::WriteAllText($mapFile, (($lines -join "`n")+"`n"), (New-Object System.Text.UTF8Encoding($false))) } catch {}
exit 0
