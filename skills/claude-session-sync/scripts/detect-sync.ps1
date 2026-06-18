<#  claude-session-sync : 同期フォルダ候補を自動検出 (Windows)
    出力: 1行 = "LABEL<TAB>PATH"  #>
$ErrorActionPreference = 'SilentlyContinue'
$cands = [ordered]@{}
foreach($v in 'OneDrive','OneDriveConsumer','OneDriveCommercial'){
  $p = [Environment]::GetEnvironmentVariable($v); if($p -and (Test-Path $p)){ $cands["OneDrive ($v)"] = $p }
}
$ic = Join-Path $env:USERPROFILE 'iCloudDrive'; if(Test-Path $ic){ $cands['iCloud Drive'] = $ic }
$db = Join-Path $env:USERPROFILE 'Dropbox';     if(Test-Path $db){ $cands['Dropbox'] = $db }
$gd = Join-Path $env:USERPROFILE 'Google Drive';if(Test-Path $gd){ $cands['Google Drive'] = $gd }
$stcfg = Join-Path $env:LOCALAPPDATA 'Syncthing\config.xml'
if(Test-Path $stcfg){
  try { [xml]$x = Get-Content $stcfg -Raw
    foreach($f in $x.configuration.folder){ if($f.path -and (Test-Path $f.path)){ $cands["Syncthing: $($f.label)"] = $f.path } }
  } catch {}
}
foreach($k in $cands.Keys){ "$k`t$($cands[$k])" }
