<#  claude-session-sync : デバイス切替検知 + 同期/移行の健全性チェック + 起動オプション記録 (Windows / SessionStart)
    1) 会話ごとの「直近デバイス + 作業フォルダ」を lastseen.map に記録し、別デバイスでの再開を検知して
       その旨と「このデバイスでの対応する作業パス(検証済)」+ 同期/移行の健全性を stdout で Claude に伝える。
    2) 起動オプション(model/effort/permission)を launchopts.map に記録(再開時の引き継ぎ用)。
       env CSS_LAUNCH_MODEL/EFFORT/PERM があれば優先、無ければ stdin の model と既存値を保持。
    conf の deviceSwitchNotice=false で 1) の通知のみ無効化(記録は継続)。  #>
$ErrorActionPreference = 'SilentlyContinue'
if($env:CSS_TITLEGEN){ exit 0 }
# フック出力は Claude が UTF-8 で読む。WinPS5.1 の既定出力(CP932)だと日本語が化けるので UTF-8 バイト列を直接書く。
function CssEmit([string]$s){
  try{ $b=[System.Text.Encoding]::UTF8.GetBytes($s+"`n"); $o=[System.Console]::OpenStandardOutput(); $o.Write($b,0,$b.Length); $o.Flush() }
  catch{ Write-Output $s }
}
# lastseen.map(共有=攻撃者が書ける)や transcript 由来の値を Claude 文脈へ出す前にサニタイズ(制御文字/ESC除去・長さ制限)。
function San([string]$s,[int]$n){ if(-not $s){ return '' }; $s=($s -replace '[\x00-\x1F\x7F]',''); if($s.Length -gt $n){ $s=$s.Substring(0,$n) }; $s }
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ exit 0 }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$notice = -not ($cfg.ContainsKey('deviceSwitchNotice') -and $cfg.deviceSwitchNotice -eq 'false')

# stdin(UTF-8): session_id / cwd / model
$sid=''; $cwd=(Get-Location).Path; $smodel=''
try {
  $reader = New-Object System.IO.StreamReader([System.Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
  $raw = $reader.ReadToEnd(); $reader.Dispose()
  if($raw){ $j = $raw | ConvertFrom-Json; if($j.session_id){ $sid=$j.session_id }; if($j.cwd){ $cwd=$j.cwd }; if($j.model){ $smodel=$j.model } }
} catch {}
if(-not $sid){ exit 0 }

$dev = if($cfg.deviceName){ $cfg.deviceName } else { $env:COMPUTERNAME }
$mapDir = if($cfg.share){ Join-Path $cfg.share 'sessions' } else { Join-Path $claude 'sessions' }
New-Item -ItemType Directory -Force -Path $mapDir | Out-Null
$lastseen = Join-Path $mapDir 'lastseen.map'
$launchmap = Join-Path $mapDir 'launchopts.map'

function With-Lock($path,[scriptblock]$body){
  $lk="$path.lock"; $fsh=$null
  for($i=0;$i -lt 30;$i++){ try{ $fsh=[System.IO.File]::Open($lk,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None); break }catch{ Start-Sleep -Milliseconds 30 } }
  try{ & $body } finally { if($fsh){ $fsh.Close() }; try{ [System.IO.File]::Delete($lk) }catch{} }
}
function Map-Get($file,$key){ if(Test-Path $file){ foreach($l in (Get-Content $file -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if($a[0] -eq $key){ return $a } } }; return $null }
function Map-Set($file,$key,[string[]]$fields){
  With-Lock $file {
    $lines=@(); if(Test-Path $file){ foreach($l in (Get-Content $file -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if($a[0] -ne $key){ $lines+=$l } } }
    $lines += ((@($key)+$fields) -join "`t")
    [System.IO.File]::WriteAllText($file, (($lines -join "`n")+"`n"), (New-Object System.Text.UTF8Encoding($false)))
  }
}

# ---- 1) 起動オプションの記録(再開時の引き継ぎ用)。env 優先・無ければ既存保持 ----
$prev = Map-Get $launchmap $sid
$pModel = if($prev -and $prev.Count -ge 2){ $prev[1] } else { '' }
$pEff   = if($prev -and $prev.Count -ge 3){ $prev[2] } else { '' }
$pPerm  = if($prev -and $prev.Count -ge 4){ $prev[3] } else { '' }
$nModel = if($env:CSS_LAUNCH_MODEL){ $env:CSS_LAUNCH_MODEL } elseif($smodel){ $smodel } else { $pModel }
$nEff   = if($null -ne $env:CSS_LAUNCH_EFFORT -and $env:CSS_LAUNCH_EFFORT -ne ''){ $env:CSS_LAUNCH_EFFORT } else { $pEff }
$nPerm  = if($null -ne $env:CSS_LAUNCH_PERM -and $env:CSS_LAUNCH_PERM -ne ''){ $env:CSS_LAUNCH_PERM } else { $pPerm }
Map-Set $launchmap $sid @($nModel,$nEff,$nPerm,(Get-Date -Format s))

# ---- 1b) 文脈引き継ぎ(newctx)で起動された場合、新 sid -> 引き継ぎ元 sid を carryover.map に記録(履歴UIの [引継元] 表示用) ----
if($env:CSS_CARRYOVER_SRC -and ($env:CSS_CARRYOVER_SRC -ne $sid)){
  $carrymap = Join-Path $mapDir 'carryover.map'
  if(-not (Map-Get $carrymap $sid)){ Map-Set $carrymap $sid @($env:CSS_CARRYOVER_SRC,(Get-Date -Format s)) }
}

# ---- 1c) この会話をこのデバイスで開いた作業フォルダを sessionpaths.map(sid<TAB>device<TAB>cwd<TAB>時刻)に記録 ----
# 履歴UI(claude -h)のクロスデバイス再開先解決で最優先に使う。全起動方式(ch/cc/-r/素の claude)で毎回上書き記録。
if($cwd){
  $sessionpaths = Join-Path $mapDir 'sessionpaths.map'
  With-Lock $sessionpaths {
    $lines=@(); if(Test-Path $sessionpaths){ foreach($l in (Get-Content $sessionpaths -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if(-not ($a.Count -ge 2 -and $a[0] -eq $sid -and $a[1] -eq $dev)){ $lines+=$l } } }
    $lines += ((@($sid,$dev,$cwd,(Get-Date -Format s)) -join "`t"))
    [System.IO.File]::WriteAllText($sessionpaths, (($lines -join "`n")+"`n"), (New-Object System.Text.UTF8Encoding($false)))
  }
}

# ---- 2) デバイス切替の検知・通知(+ 同期/移行の健全性) ----
if($notice){
  function Translate-Path([string]$p){
    if(-not $p){ return $null }
    if(Test-Path $p){ return $p }
    $rel=$null
    if($p -match '^[A-Za-z]:\\Users\\[^\\]+\\(.+)$'){ $rel = ($matches[1] -replace '\\','/') }
    elseif($p -match '^/Users/[^/]+/(.+)$'){ $rel = $matches[1] }
    elseif($p -match '^/home/[^/]+/(.+)$'){ $rel = $matches[1] }
    elseif($p -match '^/root/(.+)$'){ $rel = $matches[1] }
    if($rel){ $cand = Join-Path $env:USERPROFILE ($rel -replace '/','\'); if(Test-Path $cand){ return $cand } }
    # 共有フォルダ相対: <共有葉名>/rel を この端末の共有ルート配下へ(作業フォルダが共有配下=デバイスごとにルートが違う場合の対応)
    if($cfg.share){
      $leaf = Split-Path $cfg.share -Leaf
      if($leaf){
        $parts = ($p -replace '\\','/') -split '/'
        $idx = [Array]::IndexOf($parts,$leaf)
        if($idx -ge 0 -and $idx -lt $parts.Count-1){ $cand2 = Join-Path $cfg.share (($parts[($idx+1)..($parts.Count-1)]) -join '\'); if(Test-Path $cand2){ return $cand2 } }
      }
    }
    return $null
  }
  # 同期/移行の健全性: 共有到達・履歴(この会話)の実在と競合・転送中ファイルを簡潔に確認(高速)
  function Sync-Health([string]$workPath){
    $w=@(); $share=$cfg.share
    if($share -and -not (Test-Path $share)){ return ,@("⚠ 共有フォルダ未到達($share): 同期アプリ停止/未マウントの可能性。最新でない恐れがあるので確認まで変更を控える") }
    # この会話の履歴ファイルの所在と競合
    $pj = Join-Path $claude 'projects'
    $sf = Get-ChildItem -Path $pj -Recurse -Filter "$sid.jsonl" -File -EA SilentlyContinue | Select-Object -First 1
    if($sf){
      $conf = @(Get-ChildItem -Path $sf.DirectoryName -File -EA SilentlyContinue | Where-Object { $_.Name -match 'sync-conflict' } | Select-Object -First 1)
      if($conf.Count){ $w += "⚠ 履歴フォルダに同期競合ファイルあり(例 $($conf[0].Name)): 履歴破損の恐れ。解決まで同一プロジェクトでの編集は控える" }
    } else { $w += "⚠ この会話の履歴(.jsonl)がこのデバイスに未到達の可能性(同期未完了?)" }
    # 作業フォルダ(コード側)の競合・転送中(浅くチェック=高速)
    if($workPath -and (Test-Path $workPath)){
      $wc = @(Get-ChildItem -Path $workPath -File -EA SilentlyContinue | Where-Object { $_.Name -match 'sync-conflict' -or $_.Name -like '~syncthing~*' -or $_.Name -like '.syncthing.*' } | Select-Object -First 1)
      if($wc.Count){ $w += "⚠ 作業フォルダに同期競合/転送中ファイルあり($($wc[0].Name)): 同期完了を待つ" }
    }
    ,$w
  }

  $ls = Map-Get $lastseen $sid
  $prevDev = if($ls -and $ls.Count -ge 2){ $ls[1] } else { '' }
  $prevCwd = if($ls -and $ls.Count -ge 3){ $ls[2] } else { '' }
  if($prevDev -and $prevDev -ne $dev){
    $sug = Translate-Path $prevCwd
    $health = Sync-Health $sug
    # 攻撃者が書ける共有マップ/transcript 由来の値はサニタイズしてから文脈へ($dev は自端末=ローカル)。
    $pdS=San $prevDev 40; $pcS=San $prevCwd 200; $cwdS=San $cwd 200; $sugS=San $sug 200
    $msg = "[claude-session-sync] デバイス切替を検知。前回『$pdS』(作業フォルダ: $pcS) → 現在『$dev』。"
    if($sug){ $msg += " このデバイスでの対応作業フォルダ(検証済・存在確認): 『$sugS』。以降はこのデバイスの絶対パスを使う(必要なら cd `"$sugS`")。" }
    else    { $msg += " 対応作業フォルダを自動特定できず(現在地: $cwdS)。別デバイスのパス表記は使わず、このデバイスの絶対パスで作業する。" }
    if($health.Count -gt 0){ $msg += " 【同期/移行の注意】 " + ($health -join ' / ') + " — 解消するまで重複作業や誤編集を避けること。" }
    else { $msg += " 同期/移行: 問題は検出されず(履歴・作業フォルダとも到達済・競合なし)。" }
    CssEmit $msg
  }
  Map-Set $lastseen $sid @($dev,$cwd,(Get-Date -Format s))
}
exit 0
