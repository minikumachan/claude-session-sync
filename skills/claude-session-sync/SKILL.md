---
name: claude-session-sync
description: >
  既存のファイル同期フォルダ(Syncthing / iCloud / Dropbox 等)を使って Claude Code の会話履歴
  (および任意でスキル)を複数マシン間で共有・同期し、同セッション(同プロジェクト)の同時アクセスを
  ロックで防ぐ。Windows / macOS / Linux 対応。別デバイスで始めた会話を続きから再開する取り込みも行う。
  「会話履歴を別PCと共有/同期したい」「別マシンの会話の続きをしたい」「同時起動を防ぎたい」
  「ロック付きで安全に claude を起動したい」ときに使う。
---

# claude-session-sync

Claude Code の会話履歴を**既存のファイル同期フォルダ越しに**複数マシンで共有するためのスキル。
認証情報・設定は共有せず、`~/.claude/projects`(任意で `~/.claude/skills`)だけをリンクで共有する。

## 重要な前提・原則

- **共有するもの**: `projects`(会話履歴 `.jsonl`)、任意で `skills`。`projects` 配下の `memory` も自動的に共有される。
- **共有しないもの**: `~/.claude/.credentials.json`、`settings.json`、`~/.claude.json`(oauthAccount/userID を含む)、`plugins`。`.claude` 全体は絶対に同期フォルダへ移動しない。
- **MCP**: claude.ai コネクタはアカウント連動。同じアカウントでログインすれば各マシンで自動的に使えるため同期不要。
- **パス符号化**: 履歴は `projects/<cwdの絶対パスを「英数字以外を - に置換」した名前>/<id>.jsonl` に保存される。OS が違うとフォルダ名が変わるため、`claude --resume` は他OSの会話をそのまま表示しない → 取り込みツール `resume-other` で解決する。
- **同時アクセス禁止(鉄則)**: 同じプロジェクトを2台で同時に Claude 起動すると同期競合(`.sync-conflict-*`)で履歴が壊れる。必ずロック付きランチャー `cc` で起動する。ロックは既定で**プロジェクト単位**(別プロジェクトの並行作業は許可)。

## 構成(同期フォルダ内に作られる）

```
<同期フォルダ>/_ClaudeCode/
  sessions/projects/   ← 履歴の実体(各マシンの ~/.claude/projects がここを指す)
  skills/              ← 共有スキル(任意。各マシンの ~/.claude/skills がここを指す)
  locks/               ← ロックファイル(<プロジェクト符号化名>.lock または ACTIVE.lock)
  exports/             ← 手動エクスポート用
```

各マシンの設定は `~/.claude/session-sync.local.conf`(同期されないローカルファイル)に保存:
`share=<.../_ClaudeCode>` / `linkProjects=true` / `linkSkills=true|false` / `lockScope=project|global`

## 使い方(Claude への指示)

ユーザーの依頼に応じて、OS を判定して該当スクリプトを実行する。
- OS 判定: PowerShell が使え Windows なら `scripts\*.ps1`、macOS/Linux なら `scripts/*.sh`(初回は `chmod +x scripts/*.sh`)。
- 共有フォルダのパスはユーザーに必ず確認する(同期対象フォルダの中の場所。例: SyncthingフォルダやiCloud内)。

### 1. セットアップ(初回・各マシンで一度)
共有フォルダ配下の `_ClaudeCode` パスを指定して実行。`prepare`(バックアップ＋非破壊マージ)→ `link`(実体退避＋リンク作成)の順。
**`link` フェーズは Claude を全終了してから**行う(起動中はファイルハンドルでリンク化できない)。

- Windows: `powershell -File scripts\setup.ps1 -Share '<...\_ClaudeCode>' [-WithSkills] [-LockScope project|global] [-Phase prepare|link|all]`
- macOS/Linux: `bash scripts/setup.sh --share '<.../_ClaudeCode>' [--with-skills] [--lock-scope project|global] [--phase prepare|link|all]`

セットアップ手順としては、まず `-Phase prepare` を実行(これは起動中でも安全)、その後ユーザーに Claude を全終了してもらい、別ターミナルで `-Phase link` を実行するよう案内するのが安全。

### 2. 起動(必ずこれで起動 = 同時アクセス防止)
- Windows: `powershell -File scripts\cc.ps1 [-- claudeへの引数...]`(例: `cc.ps1 --resume`)
- macOS/Linux: `bash scripts/cc.sh [claudeへの引数...]`
- 残ったロックを無視: `-Force` / `--force`。強制解除のみ: `-Unlock` / `--unlock`。

### 3. 別デバイスの会話を続きから
- 一覧: `cc … resume-other -List` / `resume-other.sh -l`
- 取り込み: `resume-other.ps1 -SessionId <id> -TargetDir '<このマシンの作業フォルダ>'`
  / `resume-other.sh <id> '<作業フォルダ>'` → 表示される `cd` と `claude --resume <id>` を実行。
- 取り込み先フォルダに**実プロジェクトのファイルが存在**している必要がある(プロジェクト自体も同期フォルダ内に置くと両マシンに揃う)。

### 4. 状態確認 / トラブル対応
- 状態: `setup.ps1 -Status` / `setup.sh --status`(config・リンク状態・ロック一覧)
- ロールバック: リンクを削除して `*_local_old` を戻す(削除されるのはリンクのみ、実体データは同期フォルダに残る)。
  - Windows: `Remove-Item ~/.claude/projects; Rename-Item ~/.claude/projects_local_old projects`
  - Unix: `rm ~/.claude/projects; mv ~/.claude/projects_local_old ~/.claude/projects`

### 5. 自動ロック(任意・フック)
`install-hooks.ps1` / `install-hooks.sh` で SessionStart/SessionEnd フックを `~/.claude/settings.json`
に追加すると、**通常の `claude` 起動でも自動でロック取得/解除**される(cc ラッパー不要)。
競合時はセッションは開始するが警告が context に注入される。解除は `-Uninstall` / `--uninstall`。
※ フックと cc は併用せず、どちらか一方を使う。

### 補助スクリプト
- `detect-sync.ps1` / `.sh`: 同期フォルダ候補(Syncthing/iCloud/Dropbox/OneDrive/Google Drive)を検出。
- `hook-lock.ps1` / `.sh`: フック本体(直接呼ばない)。
- リポジトリ直下の `install.ps1` / `install.sh`: 配置→検出→prepare→(任意)フックの一括導入。

## スマホ等からのリモート操作(参考)
別デバイスの会話を「続きから」OSをまたいで自動再開する公式手段は無い(パス符号化のため)。
外出先のスマホから自宅マシンを操作したい場合は Claude Code の **Remote Control**(`claude remote-control`、要 v2.1.51+ / claude.ai ログイン)を使う。ホストは起動し続ける必要がある。

## 安全メモ
- すべてのリンク作成前に `*_backup_<timestamp>` を作る。マージは既存ファイルを上書きしない union 方式。
- 同期の競合に備え、同期側で **File Versioning**(Syncthing 等)を有効化すると実質バックアップになる。
- 不明点があれば実行せずユーザーに確認する。
