<#  claude-session-sync : 自動ロック + 自動タイトル用フックを ~/.claude/settings.json に導入/削除 (Windows)
    通常の 'claude' 起動でも SessionStart で自動ロック・SessionEnd で自動解除され、
    Stop(応答完了)ごとに会話タイトルが内容に合わせて自動更新されるようになる。  #>
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
# 単一要素配列の JSON 崩れを避けるため pwsh 7+ で実行
if($PSVersionTable.PSVersion.Major -lt 7 -and (Get-Command pwsh -EA SilentlyContinue)){
  & pwsh -NoProfile -File $PSCommandPath @PSBoundParameters; exit $LASTEXITCODE
}
$settings  = Join-Path $env:USERPROFILE '.claude\settings.json'
$scriptDir = $PSScriptRoot
$ps = (Get-Command pwsh -EA SilentlyContinue).Source; if(-not $ps){ $ps = 'powershell' }
$acq = "`"$ps`" -NoProfile -File `"$scriptDir\hook-lock.ps1`" acquire"
$rel = "`"$ps`" -NoProfile -File `"$scriptDir\hook-lock.ps1`" release"
$ttl = "`"$ps`" -NoProfile -File `"$scriptDir\hook-title.ps1`""
$markers = @('hook-lock.ps1','hook-title.ps1')

function ToHash($o){
  if($null -eq $o){ return $null }
  if($o -is [System.Collections.IDictionary]){ $h=@{}; foreach($k in $o.Keys){ $h[$k]=ToHash $o[$k] }; return $h }
  if($o -is [System.Management.Automation.PSCustomObject]){ $h=@{}; foreach($p in $o.PSObject.Properties){ $h[$p.Name]=ToHash $p.Value }; return $h }
  if($o -is [System.Collections.IEnumerable] -and $o -isnot [string]){ return ,@($o | ForEach-Object { ToHash $_ }) }
  return $o
}
function RemoveOurs($groups){
  $out=@()
  foreach($g in @($groups)){
    $mine=$false
    if($g.hooks){ foreach($h in @($g.hooks)){ foreach($m in $markers){ if("$($h.command)" -like "*$m*"){ $mine=$true } } } }
    if(-not $mine){ $out += $g }
  }
  ,$out
}

$root = if(Test-Path $settings){ ToHash (Get-Content $settings -Raw | ConvertFrom-Json) } else { @{} }
if($null -eq $root){ $root=@{} }
if(-not $root.ContainsKey('hooks') -or $null -eq $root.hooks){ $root['hooks']=@{} }
foreach($evt in 'SessionStart','SessionEnd','Stop'){
  if(-not $root.hooks.ContainsKey($evt)){ $root.hooks[$evt]=@() }
  $root.hooks[$evt] = RemoveOurs $root.hooks[$evt]
}
if(-not $Uninstall){
  $root.hooks['SessionStart'] = @($root.hooks['SessionStart']) + @{ hooks=@(@{ type='command'; command=$acq }) }
  $root.hooks['SessionEnd']   = @($root.hooks['SessionEnd'])   + @{ hooks=@(@{ type='command'; command=$rel }) }
  $root.hooks['Stop']         = @($root.hooks['Stop'])         + @{ hooks=@(@{ type='command'; command=$ttl }) }
}
($root | ConvertTo-Json -Depth 40) | Set-Content $settings -Encoding utf8
if($Uninstall){ Write-Host "✔ 自動ロック/自動タイトルのフックを削除しました: $settings" -ForegroundColor Green }
else { Write-Host "✔ 自動ロック/自動タイトルのフックを設定しました: $settings" -ForegroundColor Green; Write-Host "  通常の 'claude' 起動で自動ロック/解除され、会話タイトルも自動更新されます(cc は不要)。" -ForegroundColor DarkGray }
