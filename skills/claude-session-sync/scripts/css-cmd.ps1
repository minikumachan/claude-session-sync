<#  claude-session-sync : 会話内コマンド ディスパッチャ (Windows)
    `/css` スキルから呼ばれる非対話コマンド。CLI 風ボックスで状態/設定を表示し、
    短いサブコマンドで設定を変更(新セッションから反映)。
    停止必須系(共有/再リンク/復元/MCP取込)は「会話中は不可」を表示。/css gui で設定GUIを別ウィンドウ起動。
      css-cmd.ps1 [sub] [a1] [a2]
        (なし)|status         状態パネル
        archive on|off          知識アーカイブ ON/OFF
        archive moc on|off      まとめ(MOC/索引)ファイルの自動作成 ON/OFF
        remote all|items        リモート方式
        remote c|cfp|ch|cc on|off  項目別リモート
        lang <code>             基本言語(+titleLang)
        autotitle on|off / devnotice on|off
        doctor / mcp            環境チェック / MCP 状態
        gui / history           設定GUI / 履歴GUI を別ウィンドウで開く
        share|restore|mcp-import → 会話中は不可(案内)
        help                    パネル(コマンド一覧)  #>
$ErrorActionPreference='SilentlyContinue'
try{ [Console]::OutputEncoding=(New-Object System.Text.UTF8Encoding($false)) }catch{}
$claude=Join-Path $env:USERPROFILE '.claude'
$cfgPath=Join-Path $claude 'session-sync.local.conf'
$scripts=Join-Path $claude 'skills\claude-session-sync\scripts'
$sub = if($args.Count -ge 1 -and "$($args[0])".Trim()){ "$($args[0])".Trim().ToLower() } else { 'status' }
$a1 = if($args.Count -ge 2){ "$($args[1])".Trim().ToLower() } else { '' }
$a2 = if($args.Count -ge 3){ "$($args[2])".Trim().ToLower() } else { '' }

function Read-Cfg { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8 -EA SilentlyContinue)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Cfg($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Set-Key($k,$v){ $h=Read-Cfg; $h[$k]=$v; Write-Cfg $h }
function DispW([string]$s){ $w=0; foreach($ch in $s.ToCharArray()){ $c=[int][char]$ch; if(($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF -and $c -ne 0x303F) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0xFFE0 -and $c -le 0xFFE6)){ $w+=2 } else { $w+=1 } }; $w }
function Pad([string]$s,[int]$w){ $d=DispW $s; if($d -lt $w){ $s+(' '*($w-$d)) } else { $s } }

if(-not (Test-Path $cfgPath)){ Write-Output '未設定です。先に setup を実行してください(claude -a)。'; return }

function Show-Panel {
  $c=Read-Cfg
  function LinkState($name,$flag){ $it=Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue; if($it -and $it.LinkType){ '共有中' } elseif($flag -eq 'true'){ '設定ON(未リンク)' } else { 'ローカル' } }
  function OnOff($k){ if("$($c[$k])" -eq 'off'){'OFF'}else{'ON'} }
  $sync="projects "+(LinkState 'projects' $c.shareProjects)+" / skills "+(LinkState 'skills' $c.shareSkills)
  $dests=@(); if($c.archiveObsidian){$dests+='Obsidian'}; if($c.archiveLocal){$dests+='ローカル'}; if($c.archiveNotion -eq 'on'){$dests+='Notion'}
  $moc= if(($c.archiveMoc) -ne 'off'){'ON'}else{'OFF(作らない)'}
  $arc= if($c.archiveEnabled -eq 'true'){ 'ON  → '+$(if($dests.Count){$dests -join ' / '}else{'(保存先未設定)'})+'   まとめ:'+$moc } else { 'OFF' }
  $rem= if($c.remoteMode -eq 'all'){ 'all (全方式で常にON)' } else { "items  c:$(OnOff 'remoteC') cfp:$(OnOff 'remoteCfp') ch:$(OnOff 'remoteCh') cc:$(OnOff 'remoteCc')" }
  $lang= if($c.lang){$c.lang}else{'auto'}
  $at= if($c.autoTitle -eq 'false'){'OFF'}else{'ON'}; $dn= if($c.deviceSwitchNotice -eq 'false'){'OFF'}else{'ON'}
  $title='╭─ Claude セッション同期 '; $W=52
  $o=@()
  $o+=$title+('─'*[Math]::Max(0,$W-(DispW $title)))
  $o+="│ "+(Pad '同期' 11)+"● "+$sync
  $o+="│ "+(Pad 'アーカイブ' 11)+"● "+$arc
  $o+="│ "+(Pad 'リモート' 11)+"● "+$rem
  $o+="│ "+(Pad '言語' 11)+"● "+$lang+"    タイトル自動: $at   切替通知: $dn"
  $o+="╰"+('─'*$W)
  $o+=" 操作:  /css archive on|off    /css archive moc on|off    /css remote all|items"
  $o+="        /css remote <c|cfp|ch|cc> on|off"
  $o+="        /css lang <ja|en|zh|…>  /css autotitle on|off  /css devnotice on|off"
  $o+="        ※ まとめ索引の項目別(自動作成/既存パス指定/作らない)は /css gui で設定"
  $o+=" 確認:  /css doctor (環境)   /css mcp (MCP状態)"
  $o+=" GUI :  /css gui  (設定を別ウィンドウで開く=矢印操作)   /css history (履歴UI)"
  $o+=" 停止必須(共有/再リンク/復元/MCP取込)は会話中は不可 ⨯ → /css gui か、claude を全終了してターミナルで"
  $o -join "`n"
}
function Blocked([string]$what){
  $o=@()
  $o+="╭─ 会話中は使用できません ⨯ "+('─'*20)
  $o+="│ 「$what」は claude を完全終了してから行う操作です"
  $o+="│ (起動中だと履歴破損・適用漏れの恐れがあるため会話中は実行不可)"
  $o+="╰"+('─'*48)
  $o+=" 方法: /css gui で設定GUIを別ウィンドウで開く"
  $o+="       または claude を全終了 → ターミナルで claude -a"
  $o -join "`n"
}
function Open-Gui([string]$file){
  $ps=(Get-Command pwsh -EA SilentlyContinue).Source; if(-not $ps){ $ps='powershell' }
  try{ Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scripts $file)); Write-Output "新しいウィンドウで開きました(矢印キーで操作してください)。" }
  catch{ Write-Output ("ウィンドウを開けませんでした。ターミナルで実行してください: "+(Join-Path $scripts $file)) }
}

$remMap=@{ c='remoteC'; cfp='remoteCfp'; ch='remoteCh'; cc='remoteCc' }
switch($sub){
  'status'    { Write-Output (Show-Panel) }
  'panel'     { Write-Output (Show-Panel) }
  'help'      { Write-Output (Show-Panel) }
  'archive'   {
    if($a1 -eq 'on' -or $a1 -eq 'off'){ Set-Key 'archiveEnabled' $(if($a1 -eq 'on'){'true'}else{'false'}); Write-Output (Show-Panel) }
    elseif($a1 -eq 'moc' -and ($a2 -eq 'on' -or $a2 -eq 'off')){ Set-Key 'archiveMoc' $a2; Write-Output (Show-Panel) }
    else { Write-Output '使い方: /css archive on|off   または   /css archive moc on|off(まとめ索引の自動作成)' }
  }
  'remote'    {
    if($a1 -eq 'all' -or $a1 -eq 'items'){ Set-Key 'remoteMode' $a1; Write-Output (Show-Panel) }
    elseif($remMap.ContainsKey($a1) -and ($a2 -eq 'on' -or $a2 -eq 'off')){ Set-Key $remMap[$a1] $a2; Write-Output (Show-Panel) }
    else { Write-Output '使い方: /css remote all|items   または   /css remote c|cfp|ch|cc on|off' }
  }
  'lang'      { if($a1){ $h=Read-Cfg; $h['lang']=$a1; $h['titleLang']=$a1; Write-Cfg $h; Write-Output (Show-Panel) } else { Write-Output '使い方: /css lang <ja|en|zh|ko|es|fr|de|pt|ru|auto>' } }
  'autotitle' { if($a1 -eq 'on' -or $a1 -eq 'off'){ Set-Key 'autoTitle' $(if($a1 -eq 'on'){'true'}else{'false'}); Write-Output (Show-Panel) } else { Write-Output '使い方: /css autotitle on|off' } }
  'devnotice' { if($a1 -eq 'on' -or $a1 -eq 'off'){ Set-Key 'deviceSwitchNotice' $(if($a1 -eq 'on'){'true'}else{'false'}); Write-Output (Show-Panel) } else { Write-Output '使い方: /css devnotice on|off' } }
  'doctor'    { & (Join-Path $scripts 'check-deps.ps1') }
  'mcp'       { & (Join-Path $scripts 'mcp-sync.ps1') -Status }
  'gui'       { Open-Gui 'autostart-ui.ps1' }
  'history'   { Open-Gui 'history-ui.ps1' }
  'share'     { Write-Output (Blocked '共有の開始 / 再リンク') }
  'restore'   { Write-Output (Blocked '元の履歴先へ復元') }
  'mcp-import'{ Write-Output (Blocked 'MCP の取り込み') }
  default     { Write-Output ("不明なコマンド: $sub"); Write-Output ''; Write-Output (Show-Panel) }
}
