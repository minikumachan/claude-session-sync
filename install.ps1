<#  claude-session-sync : ワンショットインストーラ (Windows)
    スキル配置 → 同期フォルダ選択 → 非破壊セットアップ(prepare) → (任意)自動ロックフック
    その後、Claude を全終了して  setup.ps1 -Phase link  でリンクを作成する。  #>
[CmdletBinding()]
param(
  [string]$Share,
  [switch]$Skills,
  [switch]$Mcp,
  [switch]$NoProjects,
  [switch]$Hooks,
  [ValidateSet('project','global')][string]$LockScope = 'project'
)
$ErrorActionPreference = 'Stop'
$repoSkill = Join-Path $PSScriptRoot 'skills\claude-session-sync'
$dest      = Join-Path $env:USERPROFILE '.claude\skills\claude-session-sync'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "$repoSkill\*" $dest -Recurse -Force
Write-Host "✔ スキルを配置: $dest" -ForegroundColor Green
$scripts = Join-Path $dest 'scripts'

if(-not $Share){
  Write-Host "`n同期フォルダ候補を検出中..." -ForegroundColor Cyan
  $rows = @(& "$scripts\detect-sync.ps1")
  $list = @(); $i = 0
  foreach($r in $rows){ $parts = $r -split "`t",2; $i++; $list += [pscustomobject]@{ Path=$parts[1] }; Write-Host ("  [{0}] {1}  ->  {2}" -f $i,$parts[0],$parts[1]) }
  if($list.Count -gt 0){
    $sel = Read-Host "`n番号を選択、または共有ルートのパスを直接入力"
    if($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $list.Count){ $root = $list[[int]$sel-1].Path } else { $root = $sel }
  } else {
    $root = Read-Host "同期フォルダのルートを入力してください(例: D:\Sync\MyVault)"
  }
  $Share = Join-Path $root '_ClaudeCode'
}
Write-Host "共有先(_ClaudeCode): $Share" -ForegroundColor Yellow

$sa = @('-Share', $Share, '-LockScope', $LockScope, '-Phase', 'prepare')
if($NoProjects){ $sa += '-NoProjects' }
if($Skills){ $sa += '-Skills' }
if($Mcp){ $sa += '-Mcp' }
& "$scripts\setup.ps1" @sa

if($Hooks){ & "$scripts\install-hooks.ps1" }

Write-Host "`n=== 次の手順(リンク作成・破壊的)===" -ForegroundColor Cyan
Write-Host "Claude Code を全終了してから、別ターミナルで実行:"
Write-Host "  & `"$scripts\setup.ps1`" -Phase link          # まずドライランで内容確認"
Write-Host "  & `"$scripts\setup.ps1`" -Phase link -Yes     # 同意後に実行"
if($Mcp){ Write-Host "MCP を同期するには:  & `"$scripts\mcp-sync.ps1`" -Export   /   -Import -Yes" -ForegroundColor DarkGray }
Write-Host "完了後の起動: 通常の 'claude'(フック導入時は自動ロック) もしくは ロック付き 'cc.ps1'。" -ForegroundColor DarkGray
