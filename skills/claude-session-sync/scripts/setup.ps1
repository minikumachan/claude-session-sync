<#  claude-session-sync : setup / link / status  (Windows / PowerShell 5+)

    3 つの共有コンポーネントを個別に ON/OFF: projects / skills(リンク)/ mcp(ファイル同期)。
    トランスポート(同期方式)を選べる:
      - folder : 任意の同期フォルダ(Syncthing/iCloud/Dropbox 等)に依存(既定)
      - git    : 外部同期アプリ不要。ローカルのストア git リポジトリを remote と push/pull(sync.ps1 / cc.ps1)
    破壊的な link フェーズは既定でドライラン。実行には -Yes が必須。  #>
[CmdletBinding()]
param(
  [string]$Share,
  [switch]$Projects, [switch]$NoProjects,
  [switch]$Skills,   [switch]$NoSkills,
  [switch]$Mcp,      [switch]$NoMcp,
  [ValidateSet('project','global')][string]$LockScope,
  [ValidateSet('folder','git')][string]$Transport,
  [string]$GitRemote,
  [switch]$CreateRemote,
  [string]$Lang,
  [string]$DeviceName,
  [ValidateSet('prepare','link','all','status')][string]$Phase = 'all',
  [switch]$Status,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$cfgPath = Join-Path $claude 'session-sync.local.conf'

function Read-Config { $h=[ordered]@{}; if(Test-Path $cfgPath){ foreach($l in (Get-Content $cfgPath -Encoding utf8)){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){ $h[$matches[1]]=($matches[2].TrimEnd("`r")) } } }; $h }
function Write-Config($h){ $t=(($h.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join "`n")+"`n"; [System.IO.File]::WriteAllText($cfgPath,$t,(New-Object System.Text.UTF8Encoding($false))) }  # UTF-8(BOMなし)+LF: bash の get() でも安全
function AsBool($v,[bool]$def){ if([string]::IsNullOrEmpty([string]$v)){ return $def }; return ([string]$v -eq 'true') }
function OnOff([bool]$b){ if($b){'ON'}else{'OFF'} }

$cfg = Read-Config

$compProjects = if($Projects){$true} elseif($NoProjects){$false} else { AsBool $cfg.shareProjects (AsBool $cfg.linkProjects $true) }
$compSkills   = if($Skills){$true}   elseif($NoSkills){$false}   else { AsBool $cfg.shareSkills   (AsBool $cfg.linkSkills  $false) }
$compMcp      = if($Mcp){$true}      elseif($NoMcp){$false}      else { AsBool $cfg.shareMcp $false }
if(-not $LockScope){ $LockScope = if($cfg.lockScope){ $cfg.lockScope } else { 'project' } }
$transport = if($Transport){ $Transport } elseif($cfg.transport){ $cfg.transport } else { 'folder' }
$lang = if($Lang){ $Lang } elseif($cfg.lang){ $cfg.lang } else { (Get-Culture).TwoLetterISOLanguageName }       # タイトル生成言語(既定=OS言語)
$deviceName = if($DeviceName){ $DeviceName } elseif($cfg.deviceName){ $cfg.deviceName } else { $env:COMPUTERNAME } # 同機種識別用の表示名

if($Status -or $Phase -eq 'status'){
  Write-Host "=== session-sync 状態 (Windows) ===" -ForegroundColor Cyan
  Write-Host "config: $cfgPath  存在=$(Test-Path $cfgPath)"
  Write-Host ("transport={0}  components: projects={1} skills={2} mcp={3}  (lockScope={4})" -f $transport,(OnOff $compProjects),(OnOff $compSkills),(OnOff $compMcp),$LockScope)
  Write-Host "share: $($cfg.share)"
  if($transport -eq 'git'){
    Write-Host "store: $($cfg.store)"
    Write-Host "remote: $($cfg.gitRemote)"
    if($cfg.store -and (Test-Path (Join-Path $cfg.store '.git'))){
      $locks = & git -C $cfg.store ls-remote --heads origin 'refs/heads/locks/*' 2>$null
      if($locks){ Write-Host "  リモートロック:"; $locks | ForEach-Object { Write-Host "    $_" } } else { Write-Host "  リモートロック: なし" }
    }
  }
  foreach($name in 'projects','skills'){
    $it = Get-Item (Join-Path $claude $name) -Force -EA SilentlyContinue
    if($it){ Write-Host ("  ~/.claude/{0}: LinkType={1} Target={2}" -f $name,$it.LinkType,$it.Target) }
  }
  if($cfg.share){
    $mcpFile = Join-Path $cfg.share 'mcp\servers.json'
    Write-Host "  MCP共有ファイル: $mcpFile  存在=$(Test-Path $mcpFile)"
  }
  return
}

# === git トランスポート: ローカルストア repo を準備し $Share を決める ===
if($transport -eq 'git'){
  if(-not (Get-Command git -EA SilentlyContinue)){ throw "git が見つかりません(git transport に必要)。git を導入するか -Transport folder を使ってください。" }
  $store  = if($cfg.store){ $cfg.store } else { Join-Path $claude 'session-sync-store' }
  $remote = if($GitRemote){ $GitRemote } else { $cfg.gitRemote }
  if($CreateRemote -and -not $remote){
    if(-not (Get-Command git -EA SilentlyContinue)){ throw "git が必要です。" }
    $gh = (Get-Command gh -EA SilentlyContinue).Source
    if(-not $gh){ throw "-CreateRemote には gh CLI(認証済み)が必要です。あるいは -GitRemote <url> を指定してください。" }
    $login = (& gh api user --jq '.login').Trim()
    & gh repo create "$login/claude-session-store" --private 2>&1 | Out-Null
    $remote = "https://github.com/$login/claude-session-store.git"
    Write-Host "✔ 非公開リモートを作成: $remote" -ForegroundColor Green
  }
  if(-not (Test-Path (Join-Path $store '.git'))){
    $cloned = $false
    if($remote){
      $ls = & git ls-remote --heads $remote 2>$null
      if($LASTEXITCODE -eq 0 -and $ls){ & git clone -q $remote $store; $cloned = $true }
    }
    if(-not $cloned){
      New-Item -ItemType Directory -Force -Path $store | Out-Null
      & git -C $store init -q
      & git -C $store symbolic-ref HEAD refs/heads/main
      if($remote){ & git -C $store remote add origin $remote }
    }
  } else {
    if($remote -and -not (& git -C $store remote 2>$null)){ & git -C $store remote add origin $remote }
    if(& git -C $store remote 2>$null){ & git -C $store fetch -q origin 2>$null; & git -C $store merge -q --no-edit origin/main 2>$null }
  }
  if(-not (& git -C $store config user.email 2>$null)){ & git -C $store config user.email 'claude-session-sync@localhost'; & git -C $store config user.name 'claude-session-sync' }
  $Share = Join-Path $store '_ClaudeCode'
  $cfg.store = $store; if($remote){ $cfg.gitRemote = $remote }
  Write-Host "✔ git ストア: $store  (remote: $(if($remote){$remote}else{'未設定=ローカルのみ'}))" -ForegroundColor Green
}

if(-not $Share){ $Share = $cfg.share }
if(-not $Share){ throw "共有フォルダを指定してください:  setup.ps1 -Share '<...\_ClaudeCode>'  (git の場合は -Transport git -GitRemote <url>)" }
$Share = $Share.TrimEnd('\')

$dirs = @("$Share\sessions\projects","$Share\locks","$Share\exports")
if($compSkills){ $dirs += "$Share\skills" }
if($compMcp){ $dirs += "$Share\mcp" }
New-Item -ItemType Directory -Force -Path $dirs | Out-Null

$cfg.share = $Share
$cfg.shareProjects = "$compProjects".ToLower()
$cfg.shareSkills   = "$compSkills".ToLower()
$cfg.shareMcp      = "$compMcp".ToLower()
$cfg.lockScope     = $LockScope
$cfg.transport     = $transport
$cfg.lang          = $lang
$cfg.deviceName    = $deviceName
$cfg.Remove('linkProjects') | Out-Null; $cfg.Remove('linkSkills') | Out-Null
Write-Config $cfg
Write-Host ("✔ config 保存: transport={0} projects={1} skills={2} mcp={3}" -f $transport,(OnOff $compProjects),(OnOff $compSkills),(OnOff $compMcp)) -ForegroundColor Green

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

# --- git: 初期 commit + push ---
if($transport -eq 'git'){
  $store = $cfg.store
  & git -C $store config core.autocrlf false 2>$null   # EOL正規化で .jsonl が破損しないよう無効化
  $ga = Join-Path $store '.gitattributes'
  if(-not (Test-Path $ga)){ [System.IO.File]::WriteAllText($ga, "* -text`n", (New-Object System.Text.UTF8Encoding($false))) }
  foreach($d in $dirs){ $k = Join-Path $d '.gitkeep'; if(-not (Test-Path $k)){ '' | Set-Content $k -Encoding ascii } }  # 空ディレクトリも追跡
  & git -C $store add -A
  if(& git -C $store status --porcelain){ & git -C $store commit -q -m "init store $(Get-Date -Format s) $env:COMPUTERNAME" }
  if(& git -C $store remote 2>$null){
    & git -C $store branch -M main 2>$null
    & git -C $store push -u origin main 2>&1 | Out-Host
    Write-Host "✔ git ストアを remote へ push(以後 cc.ps1 が pull/push を自動化)" -ForegroundColor Green
  } else {
    Write-Host "ℹ remote 未設定。後で  setup.ps1 -Transport git -GitRemote <url>  で接続できます。" -ForegroundColor DarkGray
  }
}

# --- MCP の案内 ---
if($compMcp){
  Write-Host ""
  Write-Host "ℹ MCP 共有は ON。mcp-sync.ps1 -Export / -Import -Yes で同期(~/.claude.json はリンクしない)。" -ForegroundColor Cyan
}
Write-Host "`n完了。起動は cc.ps1 / 別デバイス会話の取り込みは resume-other.ps1。" -ForegroundColor Cyan
