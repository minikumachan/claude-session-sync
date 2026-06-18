# claude-session-sync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-skill%20%2B%20plugin-8A2BE2)

[English (README.md)](README.md) | **日本語** ・ [変更履歴](CHANGELOG.ja.md)

## これは何?
**Claude Code の会話履歴を、あなたの複数のパソコン(Windows・Mac・Linux)で共有する**ためのツールです。
たとえば「自宅の Windows で始めた会話を、外出先の MacBook で見る」ことができます。
さらに、**同じ作業を2台で同時に開いて履歴が壊れる事故を防ぐ**仕組みも入っています。

会話履歴の置き場所には、**あなたがすでに使っているクラウド同期フォルダ**(Syncthing / iCloud / Dropbox / OneDrive / Google ドライブ)を利用します。
同期サービスを使っていない場合は、**この道具だけで同期する方法(GitHub 経由)**も選べます。

## 何ができる?
- 🔁 **会話履歴をパソコン間で共有**(Windows ⇄ Mac など、台数は無制限)。
- 🧩 共有する物を**3種類から選べます**:会話履歴 / スキル / MCP設定(必要な物だけ ON)。
- 🔒 **同じプロジェクトの同時編集を自動でブロック**(別プロジェクトの同時作業は OK)。
- 🗂 **`claude -h` で全履歴をタブ＆ページで一覧**(後述)。どのパソコンの会話かが色とラベルで分かります。
- 🔐 **パスワードや設定は共有しません**(ログイン情報などは各パソコンに残ります)。
- 🛟 **安全第一**:消したり置き換えたりする操作は、まず「予行演習(ドライラン)」で内容を表示し、`-Yes` を付けたときだけ実行。実行前に必ずバックアップを作ります。

## かんたん用語
- **同期フォルダ**: Syncthing / iCloud など、複数パソコンで中身が自動的に揃うフォルダ。
- **リンク**: フォルダの「分身(ショートカットの強力版)」。Claude の履歴フォルダを同期フォルダに向けるのに使います。
- **コンポーネント**: 共有する対象の単位。`projects`(会話履歴)/ `skills` / `mcp` の3つ。
- **同期方式(2種)**: `folder`=お使いの同期アプリに任せる / `git`=この道具が GitHub 経由で同期(同期アプリ不要)。

## インストール
```bash
git clone https://github.com/minikumachan/claude-session-sync
cd claude-session-sync
# 引数なしで対話形式(共有する?→何を共有?→どのフォルダ?→の順に質問):
pwsh -File install.ps1     # Windows
bash install.sh           # macOS / Linux
```
インストーラは安全な準備までを自動で行い、**実際にリンクを作る操作はあなたが最後に実行**します(まず内容確認 → 同意して実行):
```powershell
# Windows: Claude をすべて終了してから
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link        # 予行演習(内容確認)
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link -Yes   # 実行
```
> プラグインとしても導入できます: `/plugin marketplace add minikumachan/claude-session-sync` → `/plugin install claude-session-sync`

## 使い方
| やりたいこと | コマンド |
|---|---|
| いつもの「続きから」(公式)| **`claude -r`** — Claude 公式の画面そのまま。今いるプロジェクトの履歴が出ます。 |
| **全パソコンの履歴をまとめて見る** | **`claude -h`** — タブ切替の履歴ブラウザ(下記)。`install-shell-wrap` の導入で使えます。 |
| 同時編集を防いで起動 | `cc.ps1` / `cc.sh`(`claude` の代わりに使う。引数はそのまま渡せます)|
| 状態を確認 | `setup.ps1 -Status` / `setup.sh --status` |
| 共有する物を変更 | `setup` を `-Skills` / `-Mcp` / `-NoProjects` 等を付けて再実行 |
| このパソコンの表示名を設定 | `setup.ps1 -DeviceName "自宅Win"` |

### `claude -h`(履歴ブラウザ)
公式 `claude -r` は「今いるフォルダの履歴」だけを表示します。`claude -h` は**全パソコン・全プロジェクトの履歴**を、公式に近い見た目で一覧できる画面です。
- **上部に検索ボックス**: 文字を打つだけで即フィルタ(Backspace で消去、Esc でクリア/終了)。
- **タブ**(←→で切替): `このプロジェクト` / `全履歴` / `最近7日`
- **各項目は2行表示**: 1行目=タイトル、2行目=*デバイス・件数・時刻・プロジェクト*、区切り線付き。
- **ページめくり**(PageUp / PageDown):見える分だけ順次読み込むので、件数が多くても速くて安定。
- **操作**: ↑↓で選ぶ / Enter で続きから / `/` で検索 / `q` で終了。**Mac・Linux ではマウス**(ホイール/クリック)も使えます。
- 各行に**どのパソコンの会話か**を色とラベル(`Win/名前`・`Mac/名前` 等)で表示。タイトルは Claude が付けた自動タイトルを表示します。

## 同期方式は2つ(お好みで)
| 方式 | 同期アプリ | 特徴 |
|---|---|---|
| **folder**(既定)| 必要(Syncthing / iCloud / Dropbox / OneDrive / Google ドライブ)| 既存のクラウド同期にそのまま乗る。常に自動同期。 |
| **git** | **不要** | この道具が GitHub の**非公開リポジトリ**経由で同期。同期アプリを入れたくない人向け。 |

git で使う場合: `setup.ps1 -Transport git -GitRemote <リポジトリURL>`(`-CreateRemote` で非公開リポジトリを自動作成)。
どちらでも、**ログイン情報・設定は共有されません**。

## 安全・元に戻す
- リンクを作る前に必ずバックアップ(`*_backup_時刻` / `*_local_old`)を作成します。
- 元に戻す(リンクを外すだけ。中身は同期フォルダに残ります):
  - Windows: `Remove-Item ~/.claude/projects` → `Rename-Item ~/.claude/projects_local_old projects`
  - Mac/Linux: `rm ~/.claude/projects` → `mv ~/.claude/projects_local_old ~/.claude/projects`
- 同期アプリの「バージョン履歴(File Versioning)」を有効にしておくと、さらに安心です。

## 困ったとき
- **`claude -r` で履歴が出ない**: 古い設定が残っている可能性。`install-shell-wrap` を入れ直すと公式の `claude -r` に戻ります。その後**新しいターミナル**を開いてください。
- **`claude -h` が動かない**: `install-shell-wrap.ps1`(/ `.sh`)を実行 → 新しいターミナルを開く。
- **Windows でスクリプトがブロックされる**: `powershell -ExecutionPolicy Bypass -File <スクリプト>` で実行、または一度だけ `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。
- **同じプロジェクトを2台で同時に開かない**: ロックが守ってくれますが、起動は `cc` か自動ロック(フック)のどちらかに統一してください。

## 動作環境
- Windows / macOS / Linux。Claude Code が必要。
- `git` は git 方式のときだけ。`python3` は Mac/Linux の一部機能(`claude -h` など)で使用。Windows は PowerShell(5.1 でも 7 でも可)。

## ライセンス
MIT — [LICENSE](LICENSE) を参照。
