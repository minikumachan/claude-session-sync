<#  claude-session-sync : 対話インストーラ (Windows)

    既定(対話モード)では順に質問しながら進む:
      1. スキルを ~/.claude/skills へ配置
      2. 履歴を「共有する / 既存の ~/.claude のまま(共有しない)」を選択
      3. 共有する場合: コンポーネント(projects/skills/mcp)を選択
      4. 同期フォルダを検出して選択(または直接入力)
      5. 非破壊セットアップ(prepare)を実行
      6. 自動ロックフックの導入可否を選択
      7. リンク作成(破壊的)の手順を案内 ※実行は別途 -Yes 付き

    非対話: -Share を渡すか -NonInteractive で、-Skills/-Mcp/-NoProjects/-Local/-Hooks を使う。  #>
[CmdletBinding()]
param(
  [string]$Share,
  [switch]$Local,            # 共有しない(スキルだけ入れる)
  [switch]$Skills,
  [switch]$Mcp,
  [switch]$NoProjects,
  [switch]$Hooks,
  [ValidateSet('project','global')][string]$LockScope = 'project',
  [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
$repoSkill = Join-Path $PSScriptRoot 'skills\claude-session-sync'
$dest      = Join-Path $env:USERPROFILE '.claude\skills\claude-session-sync'
$interactive = -not ($NonInteractive -or $Share -or $Local)

function Ask-YN($q,[bool]$def){ if(-not $interactive){ return $def }
  $d = if($def){'Y/n'}else{'y/N'}; $a = Read-Host "$q [$d]"
  if([string]::IsNullOrWhiteSpace($a)){ return $def }; return ($a -match '^(y|yes)$') }

# 1) スキル配置
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "$repoSkill\*" $dest -Recurse -Force
Write-Host "✔ スキルを配置: $dest" -ForegroundColor Green
$scripts = Join-Path $dest 'scripts'

# 2) 共有する / しない
$doShare = $true
if($Local){ $doShare = $false }
elseif($interactive){
  Write-Host "`n会話履歴の扱いを選んでください:" -ForegroundColor Cyan
  Write-Host "  [1] 共有する     … 同期フォルダ(Syncthing/iCloud等)へリンクして複数機で共有"
  Write-Host "  [2] 共有しない   … 既存の ~/.claude のまま(スキルだけ入れて後で設定)"
  $doShare = (Read-Host "選択 [1/2]") -ne '2'
}
if(-not $doShare){
  Write-Host "`n共有はしません。スキルのみ導入しました。" -ForegroundColor Green
  Write-Host "後で共有を始めるには:  & `"$scripts\setup.ps1`" -Share '<同期先\_ClaudeCode>' -Phase prepare" -ForegroundColor DarkGray
  return
}

# 3) コンポーネント選択
$compProjects = -not $NoProjects
$compSkills   = [bool]$Skills
$compMcp      = [bool]$Mcp
if($interactive){
  Write-Host "`n共有するコンポーネントを選択(ON/OFF):" -ForegroundColor Cyan
  $compProjects = Ask-YN "  projects(会話履歴)を共有しますか?" $true
  $compSkills   = Ask-YN "  skills(スキル)を共有しますか?" $false
  $compMcp      = Ask-YN "  mcp(MCPサーバ定義)を共有しますか?" $false
}

# 4) 同期フォルダ選択
if(-not $Share){
  Write-Host "`n同期フォルダ候補を検出中..." -ForegroundColor Cyan
  $rows = @(& "$scripts\detect-sync.ps1")
  $list = @(); $i = 0
  foreach($r in $rows){ $parts = $r -split "`t",2; $i++; $list += $parts[1]; Write-Host ("  [{0}] {1}  ->  {2}" -f $i,$parts[0],$parts[1]) }
  if($list.Count -gt 0){
    $sel = Read-Host "`n番号を選択、または共有ルートのパスを直接入力"
    if($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $list.Count){ $root = $list[[int]$sel-1] } else { $root = $sel }
  } else {
    $root = Read-Host "同期フォルダのルートを入力してください(例: D:\Sync\MyVault)"
  }
  $Share = Join-Path $root '_ClaudeCode'
}
Write-Host "共有先(_ClaudeCode): $Share" -ForegroundColor Yellow

# 5) prepare(非破壊)
$sa = @('-Share', $Share, '-LockScope', $LockScope, '-Phase', 'prepare')
if(-not $compProjects){ $sa += '-NoProjects' }
if($compSkills){ $sa += '-Skills' }
if($compMcp){ $sa += '-Mcp' }
& "$scripts\setup.ps1" @sa

# 6) フック
$wantHooks = $Hooks
if($interactive){ $wantHooks = Ask-YN "`n自動ロックのフックを導入しますか?(通常の 'claude' 起動で自動ロック)" $true }
if($wantHooks){ & "$scripts\install-hooks.ps1" }

# 7) リンク手順の案内(破壊的なので別実行)
Write-Host "`n=== 次の手順(リンク作成・破壊的)===" -ForegroundColor Cyan
Write-Host "Claude Code を全終了してから、別ターミナルで実行:"
Write-Host "  & `"$scripts\setup.ps1`" -Phase link          # まずドライランで内容確認"
Write-Host "  & `"$scripts\setup.ps1`" -Phase link -Yes     # 同意後に実行"
if($compMcp){ Write-Host "MCP を同期するには:  & `"$scripts\mcp-sync.ps1`" -Export   /   -Import -Yes" -ForegroundColor DarkGray }
Write-Host "完了後の起動: 通常の 'claude'(フック導入時は自動ロック) もしくは ロック付き 'cc.ps1'。" -ForegroundColor DarkGray
