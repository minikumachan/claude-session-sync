<#  claude-session-sync : リモート起動ウォッチャ (Windows)
    共有フォルダ内の trigger(inbox) を監視し、スマホ等から置かれたトリガで
    `claude --remote-control [--resume <sid>]` を起動する常駐プロセス。
    install-autostart.ps1 -Watch でログオン時の隠れ起動として登録。

    トリガの置き方(スマホから同期フォルダ <share>\remote\inbox に1ファイル置くだけ):
      ・新規リモート会話   : 例 wake.trig (中身は空でOK)
      ・特定会話を再開     : ファイル名か中身に session-id(UUID)を含める 例 resume-<sid>.trig
    起動後は claude アプリ/claude.ai に当該リモートセッションが現れるので、そこから操作。  #>
[CmdletBinding()]
param([int]$Interval)
$ErrorActionPreference = 'SilentlyContinue'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ return }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$share = $cfg.share; if(-not $share){ return }
$watchDir = if($cfg.remoteWatchDir){ $cfg.remoteWatchDir } else { Join-Path $share 'remote' }
$inbox  = Join-Path $watchDir 'inbox'
$done   = Join-Path $watchDir 'done'
$status = Join-Path $watchDir 'status'
foreach($d in @($inbox,$done,$status)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
if(-not $Interval){ $Interval = if($cfg.remoteWatchInterval){ [int]$cfg.remoteWatchInterval } else { 10 } }

function Resolve-Claude { (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source }
$psExe = if($PSVersionTable.PSVersion.Major -ge 6){ (Get-Process -Id $PID).Path } else { 'powershell' }
$pjRoot = Join-Path $claude 'projects'

# 二重起動防止(同一マシンでウォッチャは1つ)
$selfLock = Join-Path $watchDir 'watcher.lock'
$fs = $null
try { $fs = [System.IO.File]::Open($selfLock,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None) } catch { return }
$me = "machine=$env:COMPUTERNAME pid=$PID start=$(Get-Date -Format s)"; $b = [System.Text.Encoding]::UTF8.GetBytes($me); $fs.Write($b,0,$b.Length); $fs.Flush()

try {
  while($true){
    $stop = Join-Path $watchDir 'stop'
    if(Test-Path $stop){ Remove-Item $stop -Force; break }
    foreach($t in (Get-ChildItem $inbox -File -EA SilentlyContinue | Sort-Object LastWriteTime)){
      if($t.Name -eq 'watcher.lock'){ continue }
      $name = $t.BaseName
      $content = (Get-Content $t.FullName -Raw -EA SilentlyContinue)
      $blob = "$name`n$content"
      $sid = $null
      if($blob -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'){ $sid = $matches[1] }
      $cargs = @('--remote-control')
      $cwd = $env:USERPROFILE
      if($sid){
        $f = Get-ChildItem -Path $pjRoot -Recurse -Filter "$sid.jsonl" -File -EA SilentlyContinue | Select-Object -First 1
        if($f){
          try { $fl = Get-Content $f.FullName -TotalCount 1 -Encoding utf8; if($fl){ $o = $fl | ConvertFrom-Json; if($o.cwd -and (Test-Path $o.cwd)){ $cwd = $o.cwd } } } catch {}
          $cargs = @('--resume',$sid,'--remote-control')
        }
      }
      $rc = Resolve-Claude
      if($rc){
        $inner = "Set-Location -LiteralPath '$($cwd.Replace("'","''"))'; & '$($rc.Replace("'","''"))' $($cargs -join ' ')"
        Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-Command',$inner) -WorkingDirectory $cwd | Out-Null
        $ack = "started machine=$env:COMPUTERNAME sid=$sid args=$($cargs -join ' ') time=$(Get-Date -Format s)"
      } else {
        $ack = "error: claude が見つかりません time=$(Get-Date -Format s)"
      }
      [System.IO.File]::WriteAllText((Join-Path $status ("$name.ack")),$ack,(New-Object System.Text.UTF8Encoding($false)))
      $dest = Join-Path $done ("{0}_{1}" -f (Get-Date -Format yyyyMMdd_HHmmss),$t.Name)
      Move-Item $t.FullName $dest -Force
    }
    Start-Sleep -Seconds $Interval
  }
} finally {
  if($fs){ $fs.Close() }
  Remove-Item $selfLock -Force -EA SilentlyContinue
}
