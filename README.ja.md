# claude-session-sync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-skill%20%2B%20plugin-8A2BE2)

[English (README.md)](README.md) | **日本語** · [変更履歴](CHANGELOG.ja.md)

既存のファイル同期フォルダ(**Syncthing / iCloud Drive / Dropbox / OneDrive / Google Drive**)を使って、
**Claude Code の会話履歴**(と任意で**スキル**・**MCP定義**)を複数マシン間で共有し、
**同じプロジェクトを2台で同時に触って履歴を壊す事故を防ぐ**ためのツールです。

- ✅ **Windows / macOS / Linux** 対応(Win⇄Mac, Mac⇄Mac, Win⇄Win …)
- ✅ **3つのコンポーネントを個別に ON/OFF**:

  | コンポーネント | 対象 | 方式 | 既定 |
  |---|---|---|---|
  | `projects` | 会話履歴(`memory` 含む)| リンク(ジャンクション/シンボリックリンク)| ON |
  | `skills` | `~/.claude/skills` | リンク | OFF |
  | `mcp` | MCPサーバ定義(`mcpServers`)| ファイル export/import(`~/.claude.json` はリンクしない)| OFF |

- ✅ **認証情報・設定は共有しない**(`.credentials.json` / `settings.json` / `~/.claude.json` 全体 / `plugins`)
- ✅ **プロジェクト単位ロック**で同時アクセスを防止(別プロジェクトの並行作業は許可)
- ✅ 別デバイスの会話を取り込んでローカルで**続きから再開**
- ✅ **自動ロックフック**(任意)で通常の `claude` 起動も保護
- ✅ **安全第一の移行**:破壊的操作(`link` / MCP import)は **`-Yes`/`--yes` なしはドライラン**、常にバックアップ

## 仕組み
履歴は `~/.claude/projects/<cwdの絶対パスを「英数字以外を - に置換」した名前>/<id>.jsonl` に保存されます。
本ツールは `~/.claude/projects`(と任意で `~/.claude/skills`)を同期フォルダ内の `_ClaudeCode/` 配下へ
**ジャンクション(Windows)/ シンボリックリンク(mac・Linux)** で接続します。
お使いの同期ツールがほぼリアルタイムに各マシンへ反映します。

```
<同期フォルダ>/_ClaudeCode/
  sessions/projects/   ← 会話履歴の実体
  skills/              ← 共有スキル(skills が ON のとき)
  mcp/servers.json     ← 共有MCP定義(mcp が ON のとき)
  locks/               ← <プロジェクト符号化名>.lock または ACTIVE.lock
  exports/
```

> **OSをまたぐ注意**: 符号化名は OS 依存のため、同じプロジェクトでも Windows と macOS でフォルダ名が変わり、
> `claude --resume` は他OSの会話を自動表示しません → `resume-other` で取り込みます。

## トランスポート(同期方式) — folder か git
マシンごとに同期方式を選べます。

| 方式 | 外部同期アプリが必要? | 同期のしかた | リアルタイム |
|---|---|---|---|
| **folder**(既定)| **必要**(Syncthing / iCloud / Dropbox / OneDrive / GDrive)| `~/.claude/projects` を「そのアプリが同期するフォルダ」へリンク | はい(常時)|
| **git** | **不要・自己完結** | ローカルの「ストア git リポジトリ」を git remote(GitHub の**private 推奨**)と push/pull。`cc` が起動時 pull・終了時 push | セッション境界 |

> **前提となる同期サービスが無い／使いたくない**なら **git** を選べば、このスキルだけで同期が完結します。
> 排他は**リモート git ref への一意コミット push(force無し)**で行うため、2台が同じプロジェクトを同時に編集することはありません。

```powershell
# Windows: git トランスポートのセットアップ
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" `
  -Transport git -GitRemote https://github.com/<あなた>/claude-session-store.git -Phase prepare
#   (-CreateRemote で gh により private リポジトリを自動作成も可)
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link -Yes   # Claude 全終了後
```
`~/.claude.json`・認証・設定は git ストアに**入れません**(projects/skills/mcp のみ)。

## インストール

### A) 対話ウィザード(推奨)
```bash
git clone https://github.com/minikumachan/claude-session-sync
cd claude-session-sync
# 引数なしで対話モード(共有する/しない → コンポーネント → 同期フォルダ → フック の順に質問):
pwsh -File install.ps1            # Windows (PowerShell)
bash install.sh                   # macOS / Linux

# 非対話(コンポーネントを明示。projects は既定で ON):
pwsh -File install.ps1 -Skills -Mcp -Hooks
bash install.sh --skills --mcp --hooks
# スキルだけ入れて共有はしない:
pwsh -File install.ps1 -Local     #  /  bash install.sh --local
```
インストーラはスキルを `~/.claude/skills/` へ配置し、「そもそも共有するか/既存の `~/.claude` のままにするか」を選ばせ、
同期フォルダを自動検出し、**非破壊の prepare** を実行します。**破壊的なリンク作成はインストーラでは実行しません**
(コマンドを表示するだけ。Claude 全終了後に `-Yes`/`--yes` 付きで自分で実行)。

その後、リンクを作成:
```powershell
# Windows(まず -Yes なしでドライラン → 内容確認 → -Yes で実行)
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link -Yes
```
```bash
# macOS / Linux
bash "$HOME/.claude/skills/claude-session-sync/scripts/setup.sh" --phase link
bash "$HOME/.claude/skills/claude-session-sync/scripts/setup.sh" --phase link --yes
```

### B) Claude Code プラグインとして
```
/plugin marketplace add minikumachan/claude-session-sync
/plugin install claude-session-sync
```
その後、Claude に「クロスデバイスのセッション共有を設定して」と頼むと、スキルが要所で選択肢を出しながら進めます。

## 使い方

| 目的 | コマンド |
|---|---|
| ロック付きで起動 | `cc.ps1` / `cc.sh`(`claude` への引数を渡せる)|
| 全デバイスのセッション一覧 | `resume-other.ps1 -List` / `resume-other.sh -l` |
| **全履歴をどのパスからでも 閲覧/再開** | `history.ps1 list` ・ `history.ps1 view <#>` ・ `history.ps1 resume <#>`(Unix は `history.sh`)|
| **`claude -r` を全履歴対応に拡張** | `install-shell-wrap.ps1`(/ `.sh`)で `claude` 関数を追加 → 以後 `claude -r` が全パス・全デバイスの全履歴ピッカーに。エンジンは `resume-all.ps1` / `.sh`。デバイス数無制限。 |
| 別デバイスの会話を取り込み | `resume-other.* -SessionId <id> -TargetDir <作業フォルダ>` → `claude --resume <id>` |
| 状態確認(コンポーネント/リンク/MCP/ロック)| `setup.ps1 -Status` / `setup.sh --status` |
| コンポーネント切替 | `setup` を `-Skills`/`-NoSkills`・`-Mcp`/`-NoMcp`・`-NoProjects`(sh は `--skills` 等)で再実行 |
| MCP 定義を共有へ出す | `mcp-sync.ps1 -Export` / `mcp-sync.sh --export` |
| MCP 定義を取り込む(破壊的)| `mcp-sync.ps1 -Import -Yes` / `mcp-sync.sh --import --yes` |
| ロック強制解除 | `cc.ps1 -Unlock` / `cc.sh --unlock` |
| 自動ロックフック削除 | `install-hooks.ps1 -Uninstall` / `install-hooks.sh --uninstall` |

スクリプトは `~/.claude/skills/claude-session-sync/scripts/` にあります。

### ロック
既定スコープは **`project`**(作業ディレクトリ単位)。別プロジェクトは同時並行 OK、同一プロジェクトはブロック。
machine 全体で 1 つにするなら `-LockScope global`。フック導入時は `session_id` で自動ロック/解除されます。
**`cc` とフックは併用しないでください**(どちらか一方)。

## MCP 共有の安全設計
- `~/.claude.json`(oauthAccount / userID を含む)は**絶対にリンク・共有しません**。`mcpServers` だけを同期します。
- import は **自動バックアップ → 一時ファイルに書込み → JSON 検証 → 置換**。
- `env`(APIキー等)が共有フォルダに書き出される場合は**警告**。除外するには `-StripEnv` / `--strip-env`。

## スマホからのリモート操作(参考)
OSをまたいだ同一会話の自動再開はできません(パス符号化のため)。外出先からは Claude Code の
**Remote Control**(`claude remote-control`、要 v2.1.51+ / claude.ai ログイン)を使い、ホストは起動し続けます。

## 動作要件・トラブルシュート
- **必要ツール**: `claude`(常に PATH に)。`git` は **git** トランスポート時のみ。`python3` は `mcp-sync.sh` / `install-hooks.sh` / `history.sh`(mac/Linux)のみ。Windows は **PowerShell 7(`pwsh`)** 推奨で、`mcp-sync.ps1` / `install-hooks.ps1` は内部で pwsh7 に再起動するため必須。その他は **Windows PowerShell 5.1** でも動作。
- **Windows の実行ポリシー**: スクリプトがブロックされたら `powershell -ExecutionPolicy Bypass -File <script>` で実行、または一度だけ `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。(`Restricted` だとプロファイルも読み込まれず `claude -r` ラッパーが効きません。)
- **文字コード**: `.ps1` は UTF-8 **BOM付き**(WinPS 5.1 が非ASCIIを誤読するため)、`.sh` は LF・BOMなし。`.gitattributes` が clone 時に強制。`.ps1` を編集する場合は BOM を維持。
- **「`claude -r` がこのプロジェクトしか出ない」**: `install-shell-wrap` 後は**新しいターミナル**を開く(プロファイル関数はシェル起動時に読み込まれる)、または `resume-all.ps1` を直接実行。
- **git トランスポートは履歴をバイト厳密に保持**: ストアは `core.autocrlf=false` ＋ `* -text` の `.gitattributes` で `.jsonl` が EOL 変換されない。
- **クラウド(iCloud/Dropbox/OneDrive)+ `resume-all`**: 全履歴集約は終了時に掃除し Syncthing/git からは除外。これらのプロバイダでは掃除前に一時的に見えることがある。

## 安全 / ロールバック
- すべての破壊的操作の前にバックアップ(`*_backup_<時刻>` / `*_local_old` / `*.bak_<時刻>`)を作成。
- 同期側の **File Versioning**(Syncthing 等)を有効化すると実質バックアップになります。
- ロールバック(リンクのみ削除、実体は同期フォルダに残る):
  - Windows: `Remove-Item ~/.claude/projects; Rename-Item ~/.claude/projects_local_old projects`
  - Unix: `rm ~/.claude/projects; mv ~/.claude/projects_local_old ~/.claude/projects`
  - MCP は `~/.claude.json.bak_<時刻>` から復元。

## ライセンス
MIT — [LICENSE](LICENSE) を参照。
