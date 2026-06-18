<#  claude-session-sync : 別デバイスの会話を取り込んで続きから再開可能にする (Windows)  #>
[CmdletBinding()]
param([string]$SessionId, [string]$TargetDir = (Get-Location).Path, [switch]$List)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'
if(-not (Test-Path $cfgPath)){ throw "未設定です。先に setup.ps1 を実行してください。" }
$cfg = @{}; foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $cfg[$matches[1]] = ($matches[2].TrimEnd("`r")) } }
$shareProjects = Join-Path $cfg.share 'sessions\projects'
$localProjects = Join-Path $claude 'projects'
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }

if($List -or -not $SessionId){
  Write-Host "=== 共有内の会話セッション(新しい順・最大40件) ===" -ForegroundColor Cyan
  Get-ChildItem $shareProjects -Recurse -Filter *.jsonl -EA SilentlyContinue |
    Where-Object {
      (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and
      (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
      $_.BaseName -notlike 'agent-*' -and $_.BaseName -ne 'journal'
    } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 40 |
    Select-Object @{N='Updated';E={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                  @{N='KB';E={[math]::Round($_.Length/1KB)}},
                  @{N='ProjectFolder';E={Split-Path $_.DirectoryName -Leaf}},
                  @{N='SessionId';E={$_.BaseName}} | Format-Table -AutoSize
  Write-Host "取り込み: resume-other.ps1 -SessionId <id> -TargetDir <作業フォルダ>" -ForegroundColor Yellow
  return
}

$src = Get-ChildItem $shareProjects -Recurse -Filter "$SessionId.jsonl" -EA SilentlyContinue | Select-Object -First 1
if(-not $src){ throw "セッション $SessionId が共有内に見つかりません。 -List で確認してください。" }
$full = (Resolve-Path $TargetDir).Path
$destDir = Join-Path $localProjects (Encode $full)
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir "$SessionId.jsonl"
if(Test-Path $dest){ Copy-Item $dest "$dest.bak_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force }
Copy-Item $src.FullName $dest -Force
Write-Host "取り込み完了 → $dest" -ForegroundColor Green
Write-Host "続きから再開:" -ForegroundColor Cyan
Write-Host "  cd `"$full`""
Write-Host "  claude --resume $SessionId"
Write-Host "※ 対象フォルダに実プロジェクトのファイルが必要です。" -ForegroundColor DarkGray
