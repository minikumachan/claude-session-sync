<#  claude-session-sync : 全パス・全デバイスの履歴を native `claude --resume` で選べるようにする (Windows)
    Claude の --resume は「カレントのプロジェクトフォルダ」しか見ないため、
    全プロジェクトの .jsonl を「同期しないローカル集約フォルダ」へハードリンクで集約し、
    そこを作業ディレクトリにして claude --resume を起動する(native ピッカーに全件が出る)。
    集約フォルダは Syncthing(.stignore)/ git(.gitignore)から除外するので他デバイスを汚さない。
      resume-all.ps1            # 全履歴の resume ピッカーを開く
      resume-all.ps1 -DryRun    # 集約のみ(起動しない・検証用)
#>
[CmdletBinding()]
param([switch]$DryRun, [Parameter(ValueFromRemainingArguments=$true)] $ClaudeArgs)
$ErrorActionPreference='Stop'
$claude   = Join-Path $env:USERPROFILE '.claude'
$projects = Join-Path $claude 'projects'
$cfgPath  = Join-Path $claude 'session-sync.local.conf'
$cfg=@{}; if(Test-Path $cfgPath){ foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){$cfg[$matches[1]]=$matches[2]} } }
function Encode([string]$p){ $p -replace '[^A-Za-z0-9]','-' }

$hub = Join-Path $claude 'all-history'           # 集約用の作業ディレクトリ(ローカル・固定)
New-Item -ItemType Directory -Force -Path $hub | Out-Null
$enc = Encode $hub
$agg = Join-Path $projects $enc                  # native picker が読む集約フォルダ
New-Item -ItemType Directory -Force -Path $agg | Out-Null

# --- 集約フォルダを同期対象から除外(他デバイスを汚さない) ---
$realBase = if($cfg.transport -eq 'git' -and $cfg.store){ $cfg.store } elseif($cfg.share){ $cfg.share } else { $null }
$realAgg  = if($realBase){ Join-Path $realBase ("sessions\projects\"+$enc) } else { $agg }
if($realBase){
  $p = Get-Item $realBase -EA SilentlyContinue; $stroot=$null
  while($p){ if(Test-Path (Join-Path $p.FullName '.stfolder')){ $stroot=$p.FullName; break }; $p=$p.Parent }
  if($stroot){
    $rel = $realAgg.Substring($stroot.Length).TrimStart('\','/').Replace('\','/')
    $sti = Join-Path $stroot '.stignore'
    $ex  = if(Test-Path $sti){ Get-Content $sti } else { @() }
    if($ex -notcontains "/$rel"){ Add-Content $sti "/$rel" -Encoding utf8; Write-Host "Syncthing 除外に追加: /$rel" -ForegroundColor DarkGray }
  }
  if($cfg.transport -eq 'git' -and $cfg.store){
    $gi  = Join-Path $cfg.store '.gitignore'
    $rel2= $realAgg.Substring($cfg.store.Length).TrimStart('\','/').Replace('\','/')
    $ex2 = if(Test-Path $gi){ Get-Content $gi } else { @() }
    if($ex2 -notcontains $rel2){ Add-Content $gi $rel2 -Encoding utf8 }
  }
}

# --- 集約をリフレッシュ(全 .jsonl をハードリンク) ---
Get-ChildItem $agg -Filter *.jsonl -Force -EA SilentlyContinue | Remove-Item -Force
$src = Get-ChildItem $projects -Recurse -Filter *.jsonl -EA SilentlyContinue | Where-Object {
  -not $_.FullName.StartsWith($agg, [System.StringComparison]::OrdinalIgnoreCase) -and
  (Split-Path $_.DirectoryName -Leaf) -ne 'subagents' -and (Split-Path $_.DirectoryName -Leaf) -notlike 'wf_*' -and
  $_.BaseName -notlike 'agent-*' -and $_.BaseName -ne 'journal'
}
$n=0; $copy=0
foreach($f in $src){
  $lp = Join-Path $agg $f.Name
  if(-not (Test-Path $lp)){
    try { New-Item -ItemType HardLink -Path $lp -Target $f.FullName -EA Stop | Out-Null }
    catch { Copy-Item $f.FullName $lp -Force; $copy++ }
    $n++
  }
}
Write-Host "✔ 全 $n セッションを集約(全パス・全デバイス$(if($copy){" / コピー fallback $copy 件"}))。" -ForegroundColor Green
if($DryRun){ Write-Host "[DryRun] 集約のみ。フォルダ: $agg"; return }
Write-Host "native の resume ピッカーを開きます…" -ForegroundColor Cyan
# 実体の claude を直接呼ぶ(claude ラッパー関数による再帰を防止)
$realClaude = (Get-Command claude -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1).Source
if(-not $realClaude){ $realClaude = 'claude' }
Push-Location $hub
try { & $realClaude --resume @ClaudeArgs }
finally { Pop-Location }
