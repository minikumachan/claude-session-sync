# claude-session-sync(日本語)

既存のファイル同期フォルダ(**Syncthing / iCloud Drive / Dropbox / OneDrive / Google Drive**)を使って、
**Claude Code の会話履歴**(と任意で**スキル**)を複数マシン間で共有し、
**同じプロジェクトを2台で同時に触って履歴を壊す事故を防ぐ**ツールです。

- ✅ **Windows / macOS / Linux** 対応(Win⇄Mac, Mac⇄Mac, Win⇄Win …)
- ✅ 共有するのは `~/.claude/projects`(任意で `~/.claude/skills`)だけ。**認証情報・設定は共有しない**
- ✅ **プロジェクト単位ロック**で同時アクセスを防止(別プロジェクトの並行作業は許可)
- ✅ 別デバイスの会話を取り込んでローカルで**続きから再開**
- ✅ 任意の**自動ロックフック**で、通常の `claude` 起動でも保護(ラッパー不要)

> ⚠️ `~/.claude.json` / `settings.json` / `.credentials.json` / `plugins` は移動も同期もしません。認証は各マシンにローカルのまま。

## 仕組み
履歴は `~/.claude/projects/<cwdの絶対パスを「英数字以外を-」に符号化した名前>/<id>.jsonl` に保存されます。
本ツールは `~/.claude/projects` を同期フォルダ内の `_ClaudeCode/sessions/projects` へ
**ジャンクション(Windows)/ シンボリックリンク(mac・Linux)** で接続します。
OS でパス符号化が異なるため `claude --resume` は他OSの会話を自動表示しません → `resume-other` で取り込みます。

## インストール
```bash
git clone https://github.com/Minikumachan/claude-session-sync
cd claude-session-sync
# Windows: pwsh -File install.ps1 -WithSkills -Hooks
# mac/Linux: bash install.sh --with-skills --hooks
```
インストーラがスキル配置・同期フォルダ自動検出・非破壊 prepare・(任意)フック導入まで実行。
その後 **Claude を全終了**して `setup.* -Phase link` でリンクを作成します。

## 使い方
| 目的 | コマンド |
|---|---|
| ロック付きで起動 | `cc.ps1` / `cc.sh` |
| 全デバイスのセッション一覧 | `resume-other.ps1 -List` / `resume-other.sh -l` |
| 別デバイスの会話を取り込み | `resume-other.* -SessionId <id> -TargetDir <dir>` → `claude --resume <id>` |
| 状態確認 | `setup.* -Status` / `--status` |
| ロック強制解除 | `cc.ps1 -Unlock` / `cc.sh --unlock` |

詳細は英語 [README.md](README.md) を参照。MIT ライセンス。
