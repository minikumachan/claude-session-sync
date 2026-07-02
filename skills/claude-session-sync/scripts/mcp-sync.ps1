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
# 秘密検出は env だけでなく headers(HTTP/SSE の Authorization: Bearer 等)と args(--api-key=… 等)も見る。
function HasSecrets($servers){
  foreach($k in $servers.Keys){ $s=$servers[$k]
    if($s.env -and $s.env.Keys.Count -gt 0){ return $true }
    if($s.headers -and $s.headers.Keys.Count -gt 0){ return $true }
    if($s.args){ foreach($a in @($s.args)){ if("$a" -match '(?i)(key|token|secret|password|bearer|authorization|api[_-]?key)'){ return $true } } }
  }
  return $false
}
# なりすまし検知用の正規化シグネチャ(command/args/url/env/headers を値込みでキー昇順に)。値は比較のみで表示しない。
function McpSig($sv){
  $p=@("command=$($sv['command'])","url=$($sv['url'])","args=$((@($sv['args'])) -join '|')")
  foreach($coll in @('env','headers')){ $h=$sv[$coll]; if($h -and $h.Keys.Count){ $p += ($coll+'{'+ ((@($h.Keys)|Sort-Object|ForEach-Object { "$_=$($h[$_])" }) -join ';') +'}') } }
  ($p -join "`n")
}
# ローカルの MCP 定義をすべて集約: top-level(user スコープ)+ 各 projects[<cwd>].mcpServers(local スコープ)。
# `claude mcp add` は既定で local(プロジェクト)スコープに保存されるため、top-level だけ見ると空に見える。名前で重複排除(top-level 優先)。
function Collect-Local($obj){
  $all=[ordered]@{}
  if($obj.Contains('projects') -and $obj['projects']){
    foreach($pk in @($obj['projects'].Keys)){ $pm=$obj['projects'][$pk]['mcpServers']; if($pm){ foreach($s in @($pm.Keys)){ if(-not $all.Contains($s)){ $all[$s]=$pm[$s] } } } }
  }
  if($obj.Contains('mcpServers') -and $obj['mcpServers']){ foreach($s in @($obj['mcpServers'].Keys)){ $all[$s]=$obj['mcpServers'][$s] } }
  $all
}
# claude.ai 接続(Notion/Canva/Figma 等)はアカウント連携。ファイル共有の対象外であることを案内する。
function ClaudeAi-Note($obj){ $ca=@($obj['claudeAiMcpEverConnected'] | Where-Object { $_ }); if($ca.Count -gt 0){ $names=($ca | ForEach-Object { "$_" -replace '^claude\.ai ','' }) -join ', '; Write-Host "ℹ claude.ai 接続($names)はアカウント連携です。別デバイスで claude.ai にログインすれば自動で使えます(本ツールのファイル共有の対象外。`claude mcp list` で現在の接続を確認できます)。" -ForegroundColor DarkCyan } }

if(-not ($Export -or $Import)){ $Status=$true }

if($Status){
  $local=Load $localJson; $ls = Collect-Local $local
  $shared=@{}; if(Test-Path $sharedFile){ $sh=(Load $sharedFile).mcpServers; if($sh){$shared=$sh} }
  Write-Host "=== MCP 共有状態 ===" -ForegroundColor Cyan
  Write-Host "ローカル MCP 定義(user＋各プロジェクト) [$($ls.Count)]: $($ls.Keys -join ', ')"
  Write-Host "共有ファイル: $sharedFile  存在=$(Test-Path $sharedFile)"
  Write-Host "共有サーバ [$($shared.Keys.Count)]: $($shared.Keys -join ', ')"
  ClaudeAi-Note $local
  if($ls.Count -eq 0){ Write-Host "(共有できるローカル定義はありません。`claude mcp add` で追加した stdio/http 定義のみが対象です。)" -ForegroundColor DarkGray }
  return
}

if($Export){
  $local=Load $localJson
  $servers = Collect-Local $local
  if($servers.Count -eq 0){
    Write-Host "共有できるローカル MCP サーバ定義がありません(~/.claude.json の user・各プロジェクト いずれも空)。" -ForegroundColor Yellow
    ClaudeAi-Note $local
    Write-Host "→ 共有対象は `claude mcp add` で追加した stdio/http 定義のみです。claude.ai 接続は対象外(ログインで同期)。" -ForegroundColor DarkGray
    return
  }
  if($StripEnv){ foreach($k in @($servers.Keys)){ if($servers[$k].ContainsKey('env')){ $servers[$k]['env']=@{} }; if($servers[$k].ContainsKey('headers')){ $servers[$k]['headers']=@{} } } }
  $secrets = HasSecrets $servers
  if($secrets -and -not $StripEnv -and -not $Yes){
    Write-Host "⚠ 一部サーバの env / headers(Bearer等) / args に秘密(APIキー・トークン等)が含まれる可能性があります。" -ForegroundColor Red
    Write-Host "  共有フォルダ($sharedFile)に平文で書き込まれます(git同期時は remote の履歴にも恒久的に残ります)。" -ForegroundColor Yellow
    Write-Host "  続行=-Yes / env・headers を除外=-StripEnv を付けて再実行してください(args 内の秘密は自動除去されないので注意)。" -ForegroundColor Yellow
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
  if(-not (Test-Path $sharedFile)){
    Write-Host "共有 MCP 定義ファイルがまだありません: $sharedFile" -ForegroundColor Yellow
    Write-Host "→ 先に【共有元の機】で『書き出す(Export)』を実行してください。ただし共有できるのは `claude mcp add` のローカル定義のみ。" -ForegroundColor DarkGray
    ClaudeAi-Note (Load $localJson)
    return
  }
  $shared=(Load $sharedFile).mcpServers; if(-not $shared){ $shared=@{} }
  if($shared.Keys.Count -eq 0){ Write-Host "共有ファイルに MCP サーバがありません。" -ForegroundColor Yellow; return }
  $local=Load $localJson
  if(-not $local.ContainsKey('mcpServers') -or -not $local.mcpServers){ $local['mcpServers']=@{} }
  $added=@(); $updated=@()
  foreach($k in $shared.Keys){ if($local.mcpServers.ContainsKey($k)){ $updated+=$k }else{ $added+=$k } }
  Write-Host "取り込み予定: 追加=[$($added -join ', ')]  更新/上書き=[$($updated -join ', ')]" -ForegroundColor Cyan
  # 実際に入る command/args/url + env/headers のキー名を表示。既存サーバの定義(command/args/url/env/headers の値を含む)が
  # 変わる場合は警告=なりすまし(env に NODE_OPTIONS 注入、header 値すり替え等)を検知。値は表示しない(秘密漏洩防止)。
  foreach($k in $shared.Keys){
    $sv=$shared[$k]
    $line = if($sv.command){ ("{0} {1}" -f $sv.command,((@($sv.args)) -join ' ')).Trim() } elseif($sv.url){ "url: $($sv.url)" } else { '(command/url なし)' }
    $ex=@(); if($sv.env -and $sv.env.Keys.Count){ $ex+=("env:"+((@($sv.env.Keys)|Sort-Object) -join ',')) }; if($sv.headers -and $sv.headers.Keys.Count){ $ex+=("headers:"+((@($sv.headers.Keys)|Sort-Object) -join ',')) }
    $extra= if($ex.Count){ " ["+([string]::Join(' | ',$ex))+"]" } else { '' }
    $changed=''
    if($local.mcpServers.ContainsKey($k) -and (McpSig $local.mcpServers[$k]) -ne (McpSig $sv)){ $changed=' ⚠ 既存と定義が変わります(command/args/env/headers)' }
    Write-Host ("  - {0}: {1}{2}{3}" -f $k,$line,$extra,$changed) -ForegroundColor $(if($changed){'Red'}else{'DarkGray'})
  }
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
