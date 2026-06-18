<#  claude-session-sync : git トランスポート(同期サービス不要の自己完結同期)  (Windows)
    transport=git のとき、履歴ストア(ローカル git リポジトリ)を remote と push/pull し、
    プロジェクト単位の排他を「remote ref への一意孤児コミット push(force無し)」で実現する。
      pull   : remote から取り込み(マージ)
      push   : ローカル変更を commit して remote へ
      lock   : refs/heads/locks/<key> を作成(既存なら他デバイス保持として失敗 exit 2)
      unlock : ロック ref を削除
      status : ストアと remote の状態  #>
[CmdletBinding()]
param(
  [Parameter(Position=0)][ValidateSet('pull','push','status','lock','unlock')][string]$Action='status',
  [string]$Key,
  [string]$Message
)
$ErrorActionPreference='Stop'
$claude=Join-Path $env:USERPROFILE '.claude'
$cfgPath=Join-Path $claude 'session-sync.local.conf'
if(-not(Test-Path $cfgPath)){ throw "未設定です。setup.ps1 を先に実行してください。" }
$cfg=@{}; foreach($l in Get-Content $cfgPath){ if($l -match '^\s*([^=#]+?)\s*=\s*(.*)$'){$cfg[$matches[1]]=$matches[2]} }
if($cfg.transport -ne 'git'){ throw "transport=git ではありません(現在: $($cfg.transport))。" }
$store=$cfg.store
if(-not $store -or -not (Test-Path (Join-Path $store '.git'))){ throw "ストア git リポジトリがありません: $store" }
$hasRemote = [bool](& git -C $store remote 2>$null)

switch($Action){
 'status'{
   & git -C $store remote -v
   & git -C $store status -sb
 }
 'pull'{
   if(-not $hasRemote){ Write-Host "(remote 未設定: pull スキップ)" -ForegroundColor DarkGray; return }
   & git -C $store fetch -q origin
   $br = (& git -C $store symbolic-ref --short HEAD).Trim()
   & git -C $store merge --no-edit "origin/$br" 2>&1 | Out-Host
 }
 'push'{
   & git -C $store add -A
   if(& git -C $store status --porcelain){
     $m = if($Message){$Message}else{"sync $env:COMPUTERNAME $(Get-Date -Format s)"}
     & git -C $store commit -q -m $m
   }
   if($hasRemote){ & git -C $store push -q origin HEAD 2>&1 | Out-Host } else { Write-Host "(remote 未設定: ローカル commit のみ)" -ForegroundColor DarkGray }
 }
 'lock'{
   if(-not $Key){ throw 'Key が必要です' }
   if(-not $hasRemote){ Write-Host "(remote 未設定: ロックは単一マシンでは不要)" -ForegroundColor DarkGray; return }
   $LR="refs/heads/locks/$Key"
   $tree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'   # 既知の空ツリー(全リポジトリ共通)
   $msg  = "lock machine=$env:COMPUTERNAME user=$env:USERNAME pid=$PID time=$(Get-Date -Format s)"
   $commit = (& git -C $store commit-tree $tree -m $msg).Trim()
   $null = & git -C $store push origin "$($commit):$LR" 2>&1
   if($LASTEXITCODE -ne 0){
     # 既に存在 = 他デバイス保持。保持者情報を取得して表示
     & git -C $store fetch -q origin "$($LR):refs/remotes/origin/_lockpeek" 2>$null
     $who = (& git -C $store log -1 --format='%s' refs/remotes/origin/_lockpeek 2>$null)
     Write-Host "⛔ ロック取得失敗(別デバイスが使用中の可能性): $who" -ForegroundColor Red
     exit 2
   }
   Write-Host "🔒 remote lock: $Key" -ForegroundColor Green
 }
 'unlock'{
   if(-not $Key){ throw 'Key が必要です' }
   if(-not $hasRemote){ return }
   & git -C $store push origin ":refs/heads/locks/$Key" 2>&1 | Out-Host
   Write-Host "🔓 remote unlock: $Key" -ForegroundColor Green
 }
}
