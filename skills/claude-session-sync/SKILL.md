---
name: claude-session-sync
description: >
  Claude Code の会話履歴(projects)・スキル(skills)・MCPサーバ定義(mcp)を複数マシン間で共有/同期する。
  同期方式(transport)は2つ: folder(任意の同期フォルダに依存)/ git(外部同期アプリ不要・自己完結。
  履歴を git remote と push/pull)。
  3コンポーネントはそれぞれ独立に ON/OFF 可能。同セッション(同プロジェクト)の同時アクセスを
  ロックで防ぐ。Windows / macOS / Linux 対応。別デバイスで始めた会話の取り込み再開も行う。
  「会話履歴やスキルやMCPを別PCと共有/同期したい」「別マシンの会話の続きをしたい」
  「同時起動を防ぎたい」「ロック付きで安全に claude を起動したい」ときに使う。
---

# claude-session-sync

Claude Code の状態を**既存のファイル同期フォルダ越しに**複数マシンで共有するスキル。
共有するのは最大3つの**コンポーネント**だけで、各々 ON/OFF できる:

| コンポーネント | 対象 | 方式 | 既定 |
|---|---|---|---|
| **projects** | 会話履歴 `~/.claude/projects`(`memory` 含む)| リンク(ジャンクション/symlink)| ON |
| **skills** | `~/.claude/skills` | リンク | OFF |
| **mcp** | MCPサーバ定義(`~/.claude.json` の `mcpServers`)| **ファイル export/import**(リンクしない)| OFF |

**共有しないもの(常にローカル)**: `~/.claude/.credentials.json`、`settings.json`、
`~/.claude.json` 全体(oauthAccount/userID 等)、`plugins`。`.claude` 全体は絶対に同期フォルダへ移動しない。

## 🔴 確認プロトコル(最重要)
移行は**破壊的で危険**を伴う。Claude は以下を厳守する:
1. **破壊的操作の前に必ず内容を説明し、ユーザーの明示的な同意を得る**。
2. `link`(リンク化)と `mcp -Import`(~/.claude.json 書換)は **`-Yes` / `--yes` 必須**。付けない実行は
   **ドライラン**(やることと警告を表示するだけ)になる。まずドライランを見せてから同意を取る。
3. `link` は **Claude Code を完全終了してから**実行する(起動中はリネーム失敗)。
4. すべての破壊的操作の前に自動でバックアップを作る(`*_backup_<時刻>` / `*_local_old` / `*.bak_<時刻>`)。**消さない**。
5. MCP の env(APIキー等の秘密)が共有フォルダに書き出される可能性を必ず警告する。

## 対話フロー(Claude が実行するとき)
セットアップを代行する際は、一度に全部やらず**要所でユーザーに選ばせて分岐**する(AskUserQuestion 等):
1. **共有する/しない**: 「同期フォルダにリンクして共有」か「既存 `~/.claude` のまま(共有しない)」。後者ならスキル導入のみで終了。
2. **コンポーネント選択**: projects / skills / mcp をそれぞれ ON/OFF。
3. **保存先の指定**: 同期フォルダを検出候補から選ぶ or 直接パス入力(= `<選択>/_ClaudeCode`)。「既存の履歴をそのまま使う(=共有しない)」も選択肢として明示。
4. **ロック方式**: project 単位(既定)か global か。自動ロック(フック)を入れるか。
5. **破壊的実行の最終同意**: `link` / `mcp -Import` はドライランを見せてから、`-Yes`/`--yes` を付けて実行する同意を取る。
人間が自分で回す場合は対話インストーラ `install.ps1` / `install.sh`(無引数で順に質問)を使う。

## トランスポート(同期方式) — 重要
- **folder**(既定): `~/.claude/projects` 等を「外部で同期されるフォルダ」へリンク。実際の同期は Syncthing/iCloud/Dropbox/OneDrive/GDrive 等が担う(**そのアプリが必要**)。
- **git**: 外部同期アプリ**不要**で自己完結。ローカルの「ストア git リポジトリ」を **git remote(GitHub 等の private 推奨)と push/pull** して同期。`cc` が起動時に pull、終了時に push を自動実行。
  - ロックは**リモート ref への一意コミット push(force無し)**で分散排他(別デバイスが保持中なら取得失敗)。
  - 注意: 同期は git の pull/push 時点(=セッション境界)で行われ、folder のような常時リアルタイムではない。
  - セットアップ: `setup.ps1 -Transport git -GitRemote <url>`(GitHub なら `-CreateRemote` で private リポジトリ自動作成も可)。`~/.claude.json` 等の秘密は **git ストアに入れない**(従来どおり projects/skills/mcp のみ)。

どちらの transport でも projects/skills/mcp の ON/OFF と確認プロトコルは共通。「前提となる同期サービスが無い／用意したくない」利用者は **git** を選べば、このスキルだけで同期が完結する。

## 構成(同期フォルダ内 / git の場合はローカルストア内)
```
<同期フォルダ or ストア>/_ClaudeCode/
  sessions/projects/   ← 会話履歴の実体
  skills/              ← 共有スキル(skills が ON のとき)
  mcp/servers.json     ← 共有MCP定義(mcp が ON のとき)
  locks/               ← <プロジェクト符号化名>.lock または ACTIVE.lock
  exports/
```
各マシンのローカル設定: `~/.claude/session-sync.local.conf`(同期しない)
`share=<.../_ClaudeCode>` / `shareProjects` / `shareSkills` / `shareMcp` (=true|false) / `lockScope=project|global`

## 使い方(Claude への指示)
OS を判定し、Windows は `scripts\*.ps1`、macOS/Linux は `scripts/*.sh`(初回 `chmod +x scripts/*.sh`)。
共有フォルダのパスはユーザーに必ず確認する。

### 1. セットアップ(各マシンで一度)
コンポーネントを選んで指定する。`prepare`(非破壊)→ `link`(破壊的・要 `-Yes`)。
- Windows: `setup.ps1 -Share '<...\_ClaudeCode>' [-Projects|-NoProjects] [-Skills|-NoSkills] [-Mcp|-NoMcp] [-LockScope project|global] [-Lang ja|en|…] [-DeviceName <名>] -Phase prepare`
  - リンク化(全終了後): `setup.ps1 -Phase link`(ドライラン)→ 同意後 `setup.ps1 -Phase link -Yes`
- macOS/Linux: `setup.sh --share '<...>' [--projects|--no-projects] [--skills|--no-skills] [--mcp|--no-mcp] [--lock-scope ...] --phase prepare`
  - リンク化: `setup.sh --phase link` →(同意後)`setup.sh --phase link --yes`
- **git transport の場合**(`-Share` の代わりに):
  - Windows: `setup.ps1 -Transport git -GitRemote <url> [-CreateRemote] [コンポーネント] -Phase prepare` → 全終了後 `... -Phase link -Yes`
  - macOS/Linux: `setup.sh --transport git --git-remote <url> [--create-remote] ... --phase prepare` → `... --phase link --yes`

### 2. 起動(同時アクセス防止)
- `cc.ps1` / `cc.sh`(`claude` への引数をそのまま渡せる)。残骸ロック無視 `-Force`/`--force`、強制解除 `-Unlock`/`--unlock`。
- **git transport では `cc` が起動時に自動 pull + リモートロック取得、終了時に push + 解除**する。手動同期は `sync.ps1 pull|push|status|lock|unlock`(`sync.sh` 同様)。
- または自動ロックフック(下記5)。**cc とフックは併用しない**。

### 3. 履歴を見る・続きから — `claude -r`(公式)と `claude -h`(本スキルUI)
- **`claude -r`**: Claude 公式の resume ピッカー(カレントのプロジェクト=パス依存)。本スキルは**一切手を加えず公式のまま**。
- **`claude -h`**: 本スキルの履歴ブラウザ UI(`install-shell-wrap` 導入時のみ。エンジン: `history-ui.ps1` / `history-ui.sh`)。
  - **タブ式**: `[このプロジェクト(公式-rと同じパス依存)]` `[全履歴(全デバイス)]` `[最近7日]`。←→ でタブ切替。
  - **ページ式・遅延読込**: 表示中の行だけ内容を読むので、大量でも高速・安定(ページを送るたびに先を読む)。PageUp/PageDown。
  - **上部に枠付き検索ボックス**(文字入力で即フィルタ)。各項目は **2行(タイトル/メタ)＋区切り線** で表示。
  - 操作: 文字入力=検索 / Backspace=消去 / Esc=クリア(空なら終了)/ ↑↓ 選択 / ←→ タブ / PageUp,PageDown ページ / Enter 再開(現フォルダへ取り込み→`claude --resume`)/ Space 内容プレビュー。
    mac/Linux(curses)は**マウスのホイール/クリック**にも対応。Windows はキーボード操作。
  - 各行に**由来デバイスを色＋ラベル**表示(`Win/<user>` `Mac/<user>` `Linux/<user>`。**同機種**は `deviceName`/`devices.map` で識別)。
    **タイトル**は Claude の `ai-title`(無ければ冒頭発話。`titles.map` があればそれ)を表示。
- 導入/解除: `install-shell-wrap.ps1` /（Unix）`install-shell-wrap.sh`(プロファイル/rc に `claude` 関数を追加。**`-h` のみ横取り**、`-r` 含む他は公式へ素通し)。解除 `-Uninstall` / `--uninstall`。
- デバイス名は `setup -DeviceName <名>`(/ `--device-name`)で設定(既定=ホスト名。フックが起動時に `devices.map` へ記録)。

### 4. MCP 共有(mcp が ON のとき)
`~/.claude.json` はリンクせず、`mcpServers` だけを同期する。
- 状態: `mcp-sync.ps1 -Status` / `mcp-sync.sh --status`
- 共有へ出す: `mcp-sync.ps1 -Export`(env に秘密があれば `-Yes` か `-StripEnv` が必要)
- 取り込む(破壊的): `mcp-sync.ps1 -Import -Yes` / `mcp-sync.sh --import --yes`(自動バックアップ＋検証)
- 安全のため PowerShell 7+(pwsh)/ python3 を使用(単一要素配列の破壊を防止)。

### 5. 自動ロック(任意・フック)
`install-hooks.ps1` / `install-hooks.sh` で SessionStart/SessionEnd フックを `~/.claude/settings.json` に追加すると、
通常の `claude` 起動でも自動ロック/解除される(競合時は警告を注入)。解除 `-Uninstall`/`--uninstall`。

### 6. 状態確認 / ロールバック
- 状態: `setup.ps1 -Status` / `setup.sh --status`(各コンポーネントON/OFF・リンク状態・MCP・ロック)
- ロールバック(リンクのみ削除、実体は同期フォルダに残る):
  - Windows: `Remove-Item ~/.claude/projects; Rename-Item ~/.claude/projects_local_old projects`
  - Unix: `rm ~/.claude/projects; mv ~/.claude/projects_local_old ~/.claude/projects`
  - MCP は `~/.claude.json.bak_<時刻>` から復元。

### 補助
- `detect-sync.*`: 同期フォルダ候補の検出。 `hook-lock.*`: フック本体(直接呼ばない)。
- リポジトリ直下 `install.ps1` / `install.sh`: 配置→検出→prepare→(任意)フックの一括導入。

## パス符号化(再開の注意)
履歴は `projects/<cwdを「英数字以外を-」に符号化した名前>/<id>.jsonl`。OS でフォルダ名が変わるため
`claude --resume` は他OSの会話を自動表示しない → `resume-other` で取り込む。

## スマホ等からのリモート操作(参考)
OSをまたいだ同一会話の自動再開は不可。外出先からは Claude Code の **Remote Control**
(`claude remote-control`、要 v2.1.51+ / claude.ai ログイン)を使い、ホストは起動し続ける。

## 安全メモ
- 破壊的操作の前に必ずバックアップ。マージは既存を上書きしない union 方式。
- 同期側の **File Versioning**(Syncthing 等)を有効化すると実質バックアップになる。
- 不明点があれば実行せずユーザーに確認する。
