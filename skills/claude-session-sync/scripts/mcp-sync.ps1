<#  claude-session-sync : MCP サーバ定義の共有 (Windows)
    ~/.claude.json はリンクしない(oauthAccount/userID 等の機微情報を含むため)。
    mcpServers だけを 共有ファイル(_ClaudeCode/mcp/servers.json)と export/import する。
      -Status  : ローカル/共有の状態表示(既定)
      -Export  : ローカル定義 → 共有(env に秘密がある場合は -Yes か -StripEnv が必要)
      -Import  : 共有定義 → ローカル ~/.claude.json(破壊的: -Yes 必須。自動バックアップ)
    安全な JSON 編集のため PowerShell 7+(pwsh)で実行する。  #>
[CmdletBinding()]
param([switch]$Export,[switch]$Import,[switch]$Status,[switch]$StripEnv,[switch]$Yes)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7 -and (Get-Command pwsh -EA SilentlyContinue)){ & pwsh -NoProfile -File $PSCommandPath @PSBoundParameters; exit $LASTEXITCODE }
if($PSVersionTable.PSVersion.Major -lt 7){ throw "安全な JSON 編集のため PowerShell 7+(pwsh)が必要です。" }

$claude=Join-Path $env:USERPROFILE '.claude'
$cfgPath=Join-Path $claude 'session-sync.local.conf'
if(-not(Test-Path $cfgPath)){ throw "未設定です。setup.ps1 を先に実行してください。" }
$cfg=@{}; foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){$cfg[$matches[1]]=$matches[2]} }
$share=$cfg.share; if(-not $share){ throw "config に share がありません。" }
$mcpDir=Join-Path $share 'mcp'; New-Item -ItemType Directory -Force -Path $mcpDir|Out-Null
$sharedFile=Join-Path $mcpDir 'servers.json'
$localJson=Join-Path $env:USERPROFILE '.claude.json'

function Load($p){ if(Test-Path $p){ Get-Content $p -Raw | ConvertFrom-Json -AsHashtable } else { @{} } }
function HasSecrets($servers){ foreach($k in $servers.Keys){ $e=$servers[$k].env; if($e -and $e.Keys.Count -gt 0){ return $true } }; return $false }

if(-not ($Export -or $Import)){ $Status=$true }

if($Status){
  $local=Load $localJson; $ls = if($local.mcpServers){$local.mcpServers}else{@{}}
  $shared=@{}; if(Test-Path $sharedFile){ $sh=(Load $sharedFile).mcpServers; if($sh){$shared=$sh} }
  Write-Host "=== MCP 共有状態 ===" -ForegroundColor Cyan
  Write-Host "ローカル(~/.claude.json) サーバ: $($ls.Keys -join ', ')"
  Write-Host "共有ファイル: $sharedFile  存在=$(Test-Path $sharedFile)"
  Write-Host "共有サーバ: $($shared.Keys -join ', ')"
  return
}

if($Export){
  $local=Load $localJson
  $servers = if($local.mcpServers){$local.mcpServers}else{@{}}
  if($servers.Keys.Count -eq 0){ Write-Host "ローカルに MCP サーバ定義がありません(~/.claude.json)。" -ForegroundColor Yellow; return }
  if($StripEnv){ foreach($k in @($servers.Keys)){ if($servers[$k].ContainsKey('env')){ $servers[$k]['env']=@{} } } }
  $secrets = HasSecrets $servers
  if($secrets -and -not $StripEnv -and -not $Yes){
    Write-Host "⚠ 一部サーバの env に値(APIキー等の秘密の可能性)が含まれます。" -ForegroundColor Red
    Write-Host "  共有フォルダ($sharedFile)に秘密が書き込まれます。" -ForegroundColor Yellow
    Write-Host "  続行=-Yes / env を除外=-StripEnv を付けて再実行してください。" -ForegroundColor Yellow
    return
  }
  if(Test-Path $sharedFile){ Copy-Item $sharedFile "$sharedFile.bak_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force }
  $out=@{ mcpServers=$servers; _generatedBy='claude-session-sync'; _exportedFrom=$env:COMPUTERNAME }
  ($out | ConvertTo-Json -Depth 100) | Set-Content $sharedFile -Encoding utf8
  Write-Host "✔ エクスポート: $($servers.Keys.Count) サーバ → $sharedFile" -ForegroundColor Green
  if($secrets){ Write-Host "  (env を含めて書き出しました)" -ForegroundColor DarkYellow }
  return
}

if($Import){
  if(-not (Test-Path $sharedFile)){ throw "共有 MCP 定義がありません: $sharedFile(先にいずれかの機で -Export)" }
  $shared=(Load $sharedFile).mcpServers; if(-not $shared){ $shared=@{} }
  if($shared.Keys.Count -eq 0){ Write-Host "共有に MCP サーバがありません。" -ForegroundColor Yellow; return }
  $local=Load $localJson
  if(-not $local.ContainsKey('mcpServers') -or -not $local.mcpServers){ $local['mcpServers']=@{} }
  $added=@(); $updated=@()
  foreach($k in $shared.Keys){ if($local.mcpServers.ContainsKey($k)){ $updated+=$k }else{ $added+=$k } }
  Write-Host "取り込み予定: 追加=[$($added -join ', ')]  更新/上書き=[$($updated -join ', ')]" -ForegroundColor Cyan
  if(-not $Yes){
    Write-Host "⚠⚠ これは ~/.claude.json を書き換える破壊的操作です ⚠⚠" -ForegroundColor Red
    Write-Host "  実行するには -Yes を付けてください(自動でバックアップを作成し、書込み前に検証します)。" -ForegroundColor Yellow
    return
  }
  Copy-Item $localJson "$localJson.bak_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
  foreach($k in $shared.Keys){ $local.mcpServers[$k]=$shared[$k] }
  $tmp="$localJson.tmp_css"
  ($local | ConvertTo-Json -Depth 100) | Set-Content $tmp -Encoding utf8
  $null = Get-Content $tmp -Raw | ConvertFrom-Json   # 検証(壊れていれば例外)
  Move-Item $tmp $localJson -Force
  Write-Host "✔ 取り込み完了(追加 $($added.Count) / 更新 $($updated.Count))。Claude 再起動で反映。" -ForegroundColor Green
  Write-Host "  バックアップ: $localJson.bak_*" -ForegroundColor DarkGray
  if(HasSecrets $shared){ Write-Host "  env を含む定義を取り込みました。" -ForegroundColor DarkYellow }
  return
}
