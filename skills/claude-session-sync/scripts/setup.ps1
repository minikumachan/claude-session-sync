<#  claude-session-sync : setup / link / status  (Windows / PowerShell 5+)

    3 つの共有コンポーネントを個別に ON/OFF できる:
      - projects : 会話履歴   (ジャンクションでリンク)
      - skills   : ユーザースキル(ジャンクションでリンク)
      - mcp      : MCP サーバ定義(ファイルの export/import = mcp-sync.ps1。~/.claude.json はリンクしない)

    破壊的な link フェーズは既定でドライラン。実行には -Yes が必須。  #>
[CmdletBinding()]
param(
  [string]$Share,
  [switch]$Projects, [switch]$NoProjects,
  [switch]$Skills,   [switch]$NoSkills,
  [switch]$Mcp,      [switch]$NoMcp,
  [ValidateSet('project','global')][string]$LockScope,
  [ValidateSet('prepare','link','all','status')][string]$Phase = 'all',
  [switch]$Status,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=$matches[2] } } }; $h }
function Write-Config($h){ ($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`r`n" | Set-Content $cfgPath -Encoding utf8 }
function AsBool($v,[bool]$def){ if([string]::IsNullOrEmpty([string]$v)){ return $def }; return ([string]$v -eq 'true') }
function OnOff([bool]$b){ if($b){'ON'}else{'OFF'} }

$cfg = Read-Config

# --- コンポーネントの ON/OFF を解決(明示スイッチ > config > 既定) ---
$compProjects = if($Projects){$true} elseif($NoProjects){$false} else { AsBool $cfg.shareProjects (AsBool $cfg.linkProjects $true) }
$compSkills   = if($Skills){$true}   elseif($NoSkills){$false}   else { AsBool $cfg.shareSkills   (AsBool $cfg.linkSkills  $false) }
$compMcp      = if($Mcp){$true}      elseif($NoMcp){$false}      else { AsBool $cfg.shareMcp $false }
if(-not $LockScope){ $LockScope = if($cfg.lockScope){ $cfg.lockScope } else { 'project' } }

if($Status -or $Phase -eq 'status'){
  Write-Host "=== session-sync 状態 (Windows) ===" -ForegroundColor Cyan
  Write-Host "config: $cfgPath  存在=$(Test-Path $cfgPath)"
  Write-Host ("共有コンポーネント:  projects={0}  skills={1}  mcp={2}  (lockScope={3})" -f (OnOff $compProjects),(OnOff $compSkills),(OnOff $compMcp),$LockScope)
  Write-Host "share: $($cfg.share)"
  foreach($name in 'projects','skills'){
    $it = Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue
    if($it){ Write-Host ("  ~/.claude/{0}: LinkType={1} Target={2}" -f $name,$it.LinkType,$it.Target) }
  }
  if($cfg.share){
    $mcpFile = Join-Path $cfg.share 'mcp\servers.json'
    Write-Host "  MCP共有ファイル: $mcpFile  存在=$(Test-Path $mcpFile)"
    Get-ChildItem (Join-Path $cfg.share 'locks') -Filter *.lock -EA SilentlyContinue | ForEach-Object { Write-Host "  lock $($_.Name): $((Get-Content $_.FullName -Raw).Trim())" }
  }
  return
}

if(-not $Share){ $Share = $cfg.share }
if(-not $Share){ throw "共有フォルダを指定してください:  setup.ps1 -Share '<...\_ClaudeCode>'" }
$Share = $Share.TrimEnd('\')

# --- 構成作成 + config 保存 ---
$dirs = @("$Share\sessions\projects","$Share\locks","$Share\exports")
if($compSkills){ $dirs += "$Share\skills" }
if($compMcp){ $dirs += "$Share\mcp" }
New-Item -ItemType Directory -Force -Path $dirs | Out-Null

$cfg.share = $Share
$cfg.shareProjects = "$compProjects".ToLower()
$cfg.shareSkills   = "$compSkills".ToLower()
$cfg.shareMcp      = "$compMcp".ToLower()
$cfg.lockScope     = $LockScope
$cfg.Remove('linkProjects') | Out-Null; $cfg.Remove('linkSkills') | Out-Null   # 旧キーを掃除
Write-Config $cfg
Write-Host ("✔ config 保存: projects={0} skills={1} mcp={2}" -f (OnOff $compProjects),(OnOff $compSkills),(OnOff $compMcp)) -ForegroundColor Green

# リンク対象(mcp はリンクしない)
$targets = [ordered]@{}
if($compProjects){ $targets.projects = "$Share\sessions\projects" }
if($compSkills){   $targets.skills   = "$Share\skills" }

# --- prepare(非破壊: バックアップ + union マージ)---
if($Phase -in 'prepare','all'){
  foreach($name in $targets.Keys){
    $local = Join-Path $claude $name; $tgt = $targets[$name]
    $it = Get-Item $local -Force -EA SilentlyContinue
    if($it -and -not $it.LinkType){
      $stamp = Get-Date -Format yyyyMMdd_HHmmss
      robocopy $local "$claude\${name}_backup_$stamp" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
      Write-Host "✔ バックアップ: ${name}_backup_$stamp" -ForegroundColor Green
      robocopy $local $tgt /E /XN /XO /XC /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
      robocopy $tgt $local /E /XN /XO /XC /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
      Write-Host "✔ $name を非破壊マージ" -ForegroundColor Green
    }
  }
}

# --- link(破壊的: リネーム + ジャンクション。-Yes 必須)---
if($Phase -in 'link','all'){
  $todo = @()
  foreach($name in $targets.Keys){
    $local = Join-Path $claude $name
    $it = Get-Item $local -Force -EA SilentlyContinue
    if($it -and $it.LinkType){ Write-Host "• $name は既にリンク済み ($($it.Target))" -ForegroundColor DarkGray; continue }
    $todo += $name
  }
  if($todo.Count -gt 0){
    Write-Host ""
    Write-Host "⚠⚠ 破壊的な操作の確認 ⚠⚠" -ForegroundColor Red
    Write-Host "次の各フォルダを退避(*_local_old)し、共有先へのジャンクションに置き換えます: $($todo -join ', ')" -ForegroundColor Yellow
    Write-Host "・実行前に Claude Code を完全終了してください(起動中はリネーム失敗)。" -ForegroundColor Yellow
    Write-Host "・元データは *_backup_<時刻> と *_local_old に保持されます(削除しません)。" -ForegroundColor Yellow
    if(-not $Yes){
      Write-Host "→ これはドライランです。実際に変更するには  -Yes  を付けて再実行してください。" -ForegroundColor Cyan
    } else {
      foreach($name in $todo){
        $local = Join-Path $claude $name; $tgt = $targets[$name]
        try { Rename-Item $local "${name}_local_old" -ErrorAction Stop }
        catch { Write-Host "⛔ $name をリネームできません。Claude を全終了してから再実行してください。" -ForegroundColor Red; continue }
        cmd /c mklink /J "$local" "$tgt" | Out-Null
        $chk = Get-Item $local -Force -EA SilentlyContinue
        if($chk -and $chk.LinkType){ Write-Host "✔ $name → $($chk.Target)" -ForegroundColor Green }
        else { Write-Host "⛔ $name のリンク作成に失敗(退避フォルダ ${name}_local_old から復旧可)。" -ForegroundColor Red }
      }
    }
  }
}

# --- MCP の案内(リンクではなく export/import)---
if($compMcp){
  Write-Host ""
  Write-Host "ℹ MCP 共有は ON です。MCP は ~/.claude.json をリンクせず、定義ファイルの同期で行います:" -ForegroundColor Cyan
  Write-Host "   ローカル定義を共有へ:  mcp-sync.ps1 -Export" -ForegroundColor Cyan
  Write-Host "   共有定義を取り込み  :  mcp-sync.ps1 -Import -Yes   (~/.claude.json を変更。要確認)" -ForegroundColor Cyan
  Write-Host "   ⚠ MCP定義の env にAPIキー等の秘密が含まれる場合、共有フォルダに保存される点に注意。" -ForegroundColor Yellow
}
Write-Host "`n完了。起動は cc.ps1 / 別デバイス会話の取り込みは resume-other.ps1。" -ForegroundColor Cyan
