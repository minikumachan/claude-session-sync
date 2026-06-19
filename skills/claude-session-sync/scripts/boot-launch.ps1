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
function Build-Entry($e,[bool]$inline){
  $a = @(); $cwd = $env:USERPROFILE
  $type = "$($e.type)"
  if($type -eq 'last'){
    $f = Get-ChildItem -Path $pjRoot -Recurse -Filter '*.jsonl' -File -EA SilentlyContinue | Where-Object { $_.FullName -notmatch 'session-sync-titlegen' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($f){ $a += @('--resume',$f.BaseName); $c = Get-SessionCwd $f; if($c){ $cwd = $c } }
  } elseif($type -eq 'resume'){
    $sid = "$($e.sid)"; if($sid){ $a += @('--resume',$sid); $f = Get-ChildItem -Path $pjRoot -Recurse -Filter "$sid.jsonl" -File -EA SilentlyContinue | Select-Object -First 1; if($f){ $c = Get-SessionCwd $f; if($c){ $cwd = $c } } }
  } else {  # new … model/effort を反映(壁打ち)
    if($e.model){  $a += @('--model',  "$($e.model)") }
    if($e.effort){ $a += @('--effort', "$($e.effort)") }
    if($e.dir -and (Test-Path "$($e.dir)")){ $cwd = "$($e.dir)" }
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
    $inner = "Set-Location -LiteralPath '$($b.cwd.Replace("'","''"))'; & '$($rc.Replace("'","''"))' $($b.args -join ' ')"
    Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-Command',$inner) -WorkingDirectory $b.cwd | Out-Null
  }
}
