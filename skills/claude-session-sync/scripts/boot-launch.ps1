<#  claude-session-sync : PC ログオン時の自動起動ランチャー (Windows)
    自動起動する会話は複数指定でき、項目ごとに種類/モデル/思考深度/リモートを持つ。
    保存先(ローカル・非同期): ~/.claude/session-sync.boot.json  (配列)
      [{ "type":"new"|"last"|"resume", "sid":"<uuid>", "model":"sonnet",
         "effort":"medium", "remote":true|false|"ask", "dir":"<path>" }, ...]
      ・new    … 新規会話(壁打ち)。model/effort を指定可。
      ・last   … 最近の会話を再開。model/effort は無視(会話のものを使用)。
      ・resume … 特定の会話(sid)を再開。model/effort は無視(会話のものを使用)。
    旧 conf キー bootLaunch/bootRemote(単一)も後方互換で読む。
    起動前に bootCheckMulti(既定 true)で他デバイス使用中チェック=Win/Mac 同時起動防止。  #>
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'SilentlyContinue'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ Write-Host 'session-sync 未設定です。先に setup を実行してください。'; Start-Sleep 4; return }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$checkMulti = if($cfg.ContainsKey('bootCheckMulti')){ $cfg.bootCheckMulti -ne 'false' } else { $true }
$pjRoot = Join-Path $claude 'projects'

# --- 起動項目を読む(boot.json 優先、無ければ旧 conf 単一キーから合成) ---
function Read-BootEntries {
  $bj = Join-Path $claude 'session-sync.boot.json'
  if(Test-Path $bj){
    try { $arr = Get-Content $bj -Raw -Encoding utf8 | ConvertFrom-Json; if($arr){ return @($arr) } } catch {}
  }
  $bl = $cfg.bootLaunch
  if($bl -and $bl -ne 'off'){
    $rem = switch($cfg.bootRemote){ 'true'{$true} 'ask'{'ask'} default{$false} }
    if($bl -eq 'last'){ return ,@([pscustomobject]@{ type='last'; remote=$rem }) }
    if($bl -eq 'new'){ return ,@([pscustomobject]@{ type='new'; model='sonnet'; effort='medium'; remote=$rem }) }
    return ,@([pscustomobject]@{ type='resume'; sid=$bl; remote=$rem })
  }
  return @()
}
$entries = Read-BootEntries
if($entries.Count -eq 0){ return }

function Resolve-Claude { (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source }
$rc = Resolve-Claude
if(-not $rc){ Write-Host '⛔ claude コマンドが見つかりません。Claude Code を導入し PATH を確認してください。'; Start-Sleep 6; return }
$psExe = if($PSVersionTable.PSVersion.Major -ge 6){ (Get-Process -Id $PID).Path } else { 'powershell' }

# --- 多重起動チェック(他デバイスが共有ロック保持中か) ---
if($checkMulti){
  $share = $cfg.share
  if($share){
    $ld = Join-Path $share 'locks'
    if(Test-Path $ld){
      $now = Get-Date; $others = @()
      foreach($lf in (Get-ChildItem $ld -Filter *.lock -File -EA SilentlyContinue)){
        if(($now - $lf.LastWriteTime).TotalHours -gt 12){ continue }
        $c = (Get-Content $lf.FullName -Raw -EA SilentlyContinue)
        if($c -match 'machine=([^\s]+)'){ if($matches[1] -and $matches[1] -ne $env:COMPUTERNAME){ $others += $c.Trim() } }
      }
      if($others.Count -gt 0){
        Write-Host '⛔ 別デバイスで Claude が使用中の可能性があります(同時起動は履歴破損 .sync-conflict の恐れ):' -ForegroundColor Red
        $others | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
        Write-Host '自動起動を中止しました。もう一方を終了してから手動で起動してください。' -ForegroundColor Yellow
        Start-Sleep 8; return
      }
    }
  }
}

function Get-SessionCwd($file){ try{ $f = Get-Content $file.FullName -TotalCount 1 -Encoding utf8; if($f){ $o = $f | ConvertFrom-Json; if($o.cwd){ return $o.cwd } } } catch {}; return $null }
function Perm-Args([string]$perm){
  switch("$perm"){
    'full'              { ,@('--dangerously-skip-permissions') }
    'plan'              { ,@('--permission-mode','plan') }
    'acceptEdits'       { ,@('--permission-mode','acceptEdits') }
    'auto'              { ,@('--permission-mode','auto') }
    'dontAsk'           { ,@('--permission-mode','dontAsk') }
    'bypassPermissions' { ,@('--permission-mode','bypassPermissions') }
    default             { ,@() }
  }
}
function Resolve-Remote($e,[bool]$inline){
  $rem = $e.remote
  if($rem -is [bool]){ return [bool]$rem }
  if("$rem" -eq 'True'){ return $true }
  if("$rem" -eq 'ask'){
    if(-not $inline){ return $false }   # 新ウィンドウ起動分は尋ねない
    Write-Host 'リモート操作(スマホ/claude.ai から操作)を有効にしますか? [y/N] (8秒で N)' -ForegroundColor Cyan
    try {
      $deadline = (Get-Date).AddSeconds(8); $key = $null
      while((Get-Date) -lt $deadline){ if($Host.UI.RawUI.KeyAvailable){ $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); break }; Start-Sleep -Milliseconds 150 }
      return ($key -and ("$($key.Character)" -match '^[yY]$'))
    } catch { return $false }
  }
  return $false
}
# 再開時に前回の model/effort/permission を引き継ぐ(launchopts.map=フックが起動時に記録)
function Get-LaunchOpts([string]$sid){
  $r=@{ model=''; effort=''; perm='' }
  $files=@(); if($cfg.share){ $files+=(Join-Path $cfg.share 'sessions\launchopts.map') }; $files+=(Join-Path $claude 'sessions\launchopts.map')
  foreach($f in $files){ if($f -and (Test-Path $f)){ foreach($l in (Get-Content $f -Encoding utf8 -EA SilentlyContinue)){ $a=$l -split "`t"; if($a[0] -eq $sid){ if($a.Count -ge 2 -and $a[1]){ $r.model=$a[1] }; if($a.Count -ge 3 -and $a[2]){ $r.effort=$a[2] }; if($a.Count -ge 4 -and $a[3]){ $r.perm=$a[3] }; return $r } } } }
  $r
}
function Get-TranscriptModel($file){ $m=''; try{ foreach($line in (Get-Content $file.FullName -Tail 400 -Encoding utf8 -EA SilentlyContinue)){ if($line -match '"model"\s*:\s*"(claude[^"]*)"'){ $m=$matches[1] } } }catch{}; $m }

function Build-Entry($e,[bool]$inline){
  $a = @(); $cwd = $env:USERPROFILE
  $type = "$($e.type)"
  $rfile = $null; $rsid = ''
  if($type -eq 'last'){
    $rfile = Get-ChildItem -Path $pjRoot -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue | Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($rfile){ $rsid=$rfile.BaseName; $a += @('--resume',$rsid); $c = Get-SessionCwd $rfile; if($c){ $cwd = $c } }
  } elseif($type -eq 'resume'){
    $rsid = "$($e.sid)"; if($rsid){ $a += @('--resume',$rsid); $rfile = Get-ChildItem -Path $pjRoot -Recurse -Filter "$rsid.jsonl" -File -EA SilentlyContinue | Select-Object -First 1; if($rfile){ $c = Get-SessionCwd $rfile; if($c){ $cwd = $c } } }
  } else {  # new … 設定どおり model/effort/permission を反映(壁打ち)
    if($e.model){  $a += @('--model',  "$($e.model)") }
    if($e.effort){ $a += @('--effort', "$($e.effort)") }
    if($e.dir -and (Test-Path "$($e.dir)")){ $cwd = "$($e.dir)" }
    $pa = Perm-Args "$($e.permission)"; if($pa.Count){ $a += $pa }
    $env:CSS_LAUNCH_MODEL="$($e.model)"; $env:CSS_LAUNCH_EFFORT="$($e.effort)"; $env:CSS_LAUNCH_PERM="$($e.permission)"
  }
  if(($type -eq 'last' -or $type -eq 'resume') -and $rsid){
    # 会話の前回 model/effort/permission を引き継ぐ(項目で permission を明示していればそれを優先)
    $o = Get-LaunchOpts $rsid
    $im = if($o.model){ $o.model } elseif($rfile){ Get-TranscriptModel $rfile } else { '' }
    if($im){ $a += @('--model',$im) }
    if($o.effort){ $a += @('--effort',$o.effort) }
    # permission は「ローカル boot.json の明示指定(ユーザ設定・非同期)」のみ昇格を許可。
    # フォールバックの launchopts.map(共有され得る)由来 perm の full/bypassPermissions は採用しない(汚染対策)。
    $permv = if($e.permission -and "$($e.permission)" -ne 'default'){ "$($e.permission)" } else { if($o.perm -eq 'full' -or $o.perm -eq 'bypassPermissions'){ '' } else { $o.perm } }
    $pa = Perm-Args $permv; if($pa.Count){ $a += $pa }
    $env:CSS_LAUNCH_MODEL=$im; $env:CSS_LAUNCH_EFFORT=$o.effort; $env:CSS_LAUNCH_PERM=$permv
  }
  if(Resolve-Remote $e $inline){ $a += '--remote-control' }
  @{ args = $a; cwd = $cwd }
}

# 最後の項目はこのウィンドウで(inline)、それ以外は各々新ウィンドウで起動
for($i=0; $i -lt $entries.Count; $i++){
  $inline = ($i -eq $entries.Count-1)
  $b = Build-Entry $entries[$i] $inline
  Write-Host ("▶ claude {0}   (cwd={1})" -f ($b.args -join ' '),$b.cwd) -ForegroundColor Green
  if($DryRun){ continue }
  if($inline){
    if($b.cwd -and (Test-Path $b.cwd)){ Set-Location $b.cwd }
    & $rc @($b.args)
  } else {
    # セキュリティ: 各引数を単一引用符リテラルとして埋め込む(値に含まれる ; や空白でのコマンド注入を防ぐ)。cwd/実体パスも同様。
    $argStr = ($b.args | ForEach-Object { "'" + ("$_" -replace "'","''") + "'" }) -join ' '
    $inner = "Set-Location -LiteralPath '$($b.cwd.Replace("'","''"))'; & '$($rc.Replace("'","''"))' $argStr"
    Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-Command',$inner) -WorkingDirectory $b.cwd | Out-Null
  }
}
