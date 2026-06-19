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
- 🏷 **会話タイトルを自動で命名**:会話の内容と言語に合わせて、分かりやすい短いタイトルに自動で改名します(後述)。
- 🚀 **PC ログイン時に claude を自動起動**(新規 / 最近の会話 / 特定会話を再開)。起動前に**多重起動チェック**で Win/Mac 同時使用を防ぎます(後述)。
- 📱 **スマホから PC の claude を起動・操作**:Remote Control で外出先から操作。同期フォルダにトリガを置けば未起動でも起動できます(後述)。
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
- **タブ**(←→で切替): `このプロジェクト` / `全履歴` / `最近7日` / `★お気に入り`
- **各項目は2行表示**: 1行目=タイトル(お気に入りは ★ 付き)、2行目=*デバイス・件数・時刻・プロジェクト*、区切り線付き。
- **ページめくり**(PageUp / PageDown):見える分だけ順次読み込むので、件数が多くても速くて安定。
- **操作**: ↑↓で選ぶ / Enter で続きから / 文字で検索 / Esc で終了。**Mac・Linux ではマウス**(ホイール/クリック)も使えます。
- **Tab キーで操作メニュー**(選んだ会話に対して):
  - ⭐ **お気に入り 追加/解除** … `★お気に入り` タブでまとめて管理。設定は共有先に保存され**全パソコン共通**。
  - 🍴 **フォーク(分岐)** … 会話を**複製して別の分岐**として続けます。元の会話はそのまま残ります。
  - 🧵 **文脈を引き継いで新規** … その会話の要点(最初の要望＋直近のやり取り)を引き継いで、**新しい会話**を始めます。
- 各行に**どのパソコンの会話か**を色とラベル(`Win/名前`・`Mac/名前` 等)で表示。

### 会話タイトルの自動命名
会話を進めるたびに、Claude が**内容を読み取って分かりやすい短いタイトルを自動で付け直します**(例:「検索ボックスの不具合修正」)。
- **言語は会話に合わせます**(日本語の会話なら日本語のタイトル)。`titleLang` で特定言語に固定も可能。
- タイトルは `claude -h` の一覧で**最優先**で表示されます(Claude 標準の自動タイトルより優先)。共有先に保存されるので**他のパソコンからも同じタイトル**で見えます。
- 有効化: `install-hooks.ps1` /(Unix)`install-hooks.sh` を実行(応答完了ごとに更新)。オフにするには `setup.ps1 -NoAutoTitle`(/ `--no-auto-title`)。
- しくみ: 数発話ごとに、会話の冒頭抜粋だけを軽量モデル(既定 `haiku`)に渡してタイトルを生成します。**パスワード等は送りません**。生成用の一時セッションは自動で削除され、一覧にも出ません。

### ログイン時の自動起動 / スマホからのリモート起動
PC にログインしたら自動で `claude` を立ち上げたり、外出先のスマホから PC の `claude` を起動・操作できます。**管理者権限は不要**、設定は次回ログインから有効です。
```powershell
# Windows
install-autostart.ps1 -Launch new            # ログイン時に新規会話で起動
install-autostart.ps1 -Launch last -Remote   # 最近の会話を再開 + リモートON
install-autostart.ps1 -Session <会話ID>      # 特定の会話を毎回再開
install-autostart.ps1 -Watch                 # スマホからのトリガ起動を有効化
install-autostart.ps1 -Status                # 状態確認
install-autostart.ps1 -Uninstall             # 解除
```
(Mac/Linux は `install-autostart.sh --launch new` のように同じ意味のオプション)
- **どの会話で開くか**: `new`(新規)/ `last`(最近の会話を再開)/ 会話ID(特定の会話を毎回再開)。
- **多重起動チェック**: 起動前に、**別のパソコン**が同じ共有を使用中(12時間以内のロック)なら**起動を中止して警告**。Win と Mac の同時起動による履歴破損を防ぎます。
- **リモート(スマホ操作)**: `-Remote` を付けると `claude --remote-control` 付きで起動 → PC が起動していれば**スマホ/claude.ai から常時操作可**。`-RemoteMode ask` なら起動時に毎回尋ねます。※ Claude Code v2.1.51 以降 / claude.ai ログインが必要。
- **スマホから起動 + 指定会話で起動**: `-Watch` を有効にすると、同期フォルダの `<共有>/remote/inbox` を常駐監視します。スマホからそこに**ファイルを1つ置くだけ**で `claude --remote-control` が起動(ファイル名か中身に会話IDを含めればその会話を再開)。**追加のポート開放や外部公開は不要**(同期フォルダ経由)。起動後は claude アプリ/claude.ai に現れるので、そこから操作します。
- いずれも **PC が起動している間のみ**有効です(完全シャットダウンからの遠隔起動には Wake-on-LAN 等が別途必要)。

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
