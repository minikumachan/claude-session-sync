# 変更履歴 (Changelog)

[English (CHANGELOG.md)](CHANGELOG.md) | **日本語** · 本プロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/) に従います。

> **ひとことで言うと:** Claude Code の会話履歴を複数のパソコンで共有(同期アプリが無ければ GitHub 経由でも)し、
> 同じプロジェクトの同時編集による履歴破損を防ぎ、**`claude -h`** で全履歴を見られるようにする道具です
> (公式の **`claude -r`** はそのまま)。各版の最初の行が平易な要約、続く箇条書きが詳細です。

## 1.7.0
**要約:** `claude -r` を公式の動作に戻し、新しく **`claude -h`** で全パソコンの履歴をタブ＆ページで見られるようにしました。


- **`claude -r` を公式の純正ピッカーへ復帰。** `-r` を乗っ取る旧設計(`claude -r` で履歴が出ない原因)を撤去。シェルラッパーは **`-h` のみ横取り**し、`-r` を含む他は実体の `claude` へ素通し。公式のパス依存ピッカーが元通り動作します。
- **新 `claude -h` 履歴ブラウザ UI** — 公式ピッカーを参考にしたタブ式・ページ式・遅延読込の対話UI:
  - タブ: *このプロジェクト(パス依存=-rと同じ)/ 全履歴(全デバイス)/ 最近7日*(←→で切替)。
  - 表示中のページだけ読む(遅延)ので数百件でも高速・安定。PageUp/PageDown でページ送り。
  - 全環境でキーボード(↑↓選択・Enter再開・`/`検索・q終了)、**mac/Linux は python `curses` でマウスのホイール/クリック**対応。Windows はキーボード(公式 -r と同様)。
  - 各行に由来デバイス(色＋ラベル)と内容タイトル(Claude `ai-title`)。Enter で現フォルダへ取り込み `claude --resume`。
- **削除**: 単体コマンド `history` / `resume-other` / `resume-all`(`claude -h` に統合)。
- 移行: `install-shell-wrap` を再実行(旧 `-r` ブロックを除去し `-h` を導入)。

## 1.6.0
- **ページ式の履歴ビューア＋デバイス色分け＋内容タイトル。** `history list` をページ式に(`-Page` / `-PageSize`、既定20)。現ページ分だけスキャンするので数百件でも高速。各行に**由来デバイス**を色分け表示(`Win/<user>` `Mac/<user>` `Linux/<user>`。同機種・同ユーザーの別マシンはフックが `devices.map` に記録する `deviceName` で識別)、**内容由来のタイトル**(言語固定の生成タイトル > Claude の `ai-title` > 冒頭発話)を表示。
- **言語固定のタイトル生成**: `history title` が各会話を設定言語 `lang` で簡潔なタイトルに要約(`claude -p`)し `titles.map` にキャッシュ。
- **全履歴ピッカーの読込量制御**: `resume-all` / `claude -r` に `-Limit`(既定=最近100件)・`-Days`・`-All`。native picker を高速化。
- 新しい設定キー: `lang`(既定=OS言語)/ `deviceName`(既定=ホスト名)。`setup -Lang` / `-DeviceName` で設定。
- 修正: history list の `$all` と switch `$All` の同名衝突を解消。

## 1.5.1
どんな環境・利用者でも動くようにするための堅牢化(全環境監査ベース):
- **文字コード**: 全 `.ps1` を UTF-8 **BOM付き**にし、設定/`.jsonl` を `-Encoding utf8` で読込。Windows PowerShell 5.1 で日本語や非ASCIIパスが化けて構文エラーになる問題を解消。`.gitattributes` に `working-tree-encoding=UTF-8-BOM` を追加し、clone した全員が正しい BOM を取得。
- **原子的ロック**(folder): ロックファイルを `CreateNew` / `noclobber` で作成し、確認→書込みの競合(TOCTOU)を排除。
- **git ストアの整合性**: ストアを `core.autocrlf=false` ＋ `* -text` の `.gitattributes` にし、`.jsonl` が EOL 変換で壊れないように。
- **`resume-all` のクリーンアップ**: 全履歴集約を終了時に削除(`.stfolder` の無い iCloud/Dropbox/OneDrive での同期汚染を防止)。
- **事前チェックと安全性**: 状態変更前に `claude`/`git` の存在を確認し明確なエラー表示。フックの stdin を UTF-8 で読込(WinPS 5.1 で cwd が化けない)。設定は UTF-8/LF で書き CRLF 混入にも耐性。`detect-sync.sh` に `nullglob`。エクスポートした MCP 秘密ファイルを `chmod 600`。`history` は非ASCII・短いID に対応。`claude -r` ラッパーは実体バイナリを呼び再帰を防止。

## 1.5.0
- **`claude -r` を全履歴に拡張**(全パス・全デバイス)。Claude の `--resume` はカレントのプロジェクトフォルダ限定で本体も改変不可のため、`resume-all` が全セッションの `.jsonl` を**同期しないローカルの集約フォルダ**へハードリンクで集め、そこで native の `--resume` ピッカーを開く=全件が一覧に出る。
- `install-shell-wrap.ps1` / `.sh` がシェル(PowerShell プロファイル / bashrc / zshrc)に `claude` 関数を追加し、`claude -r` / `--resume` が全履歴ピッカーになる。その他の引数は実体の `claude` へ素通し。解除は `-Uninstall` / `--uninstall`。
- 集約フォルダは同期から自動除外(folder は `.stfolder` ルートの `.stignore`、git は `.gitignore`)。他デバイスを汚さない。
- **デバイス数は無制限**(folder=Syncthing/iCloud 等、git とも多数のピア/クローンに対応)。

## 1.4.0
- **`history` コマンド** — どの作業ディレクトリからでも、全プロジェクトの会話履歴を一覧/閲覧/再開(Claude 標準の `--resume` はカレントのプロジェクトのみ)。`~/.claude/projects` を直接読むので、同期された全デバイスの全プロジェクトが見える。
  - `history.ps1 list [-Grep <語>] [-Limit N]` — 全セッションを新しい順に、プロジェクト名＋冒頭プレビュー付きで。
  - `history.ps1 view <#|id>` — セッションの会話本文を読みやすく表示。
  - `history.ps1 resume <#|id>` — 現在のフォルダへ取り込み、`claude --resume` コマンドを表示。
  - `history.ps1 path <#|id>` — .jsonl のパスを表示。(macOS/Linux は `history.sh`)

## 1.3.0
- **git トランスポート** — 外部同期アプリ不要の自己完結同期。ローカルの「ストア git リポジトリ」を git remote(例: GitHub の private)と push/pull し、`cc` が起動時 pull・終了時 push。`setup --transport git --git-remote <url>`(`--create-remote` で `gh` により private リポジトリ自動作成)で選択。既存の `folder` トランスポート(Syncthing/iCloud/Dropbox/OneDrive/GDrive)が既定のまま。
- **git 用の分散ロック** — リモート git ref(force無しで push する一意の孤児コミット)で相互排他。同一プロジェクトのロックを別マシンが取ろうとすると拒否。2台シミュレーションで検証済み。
- 新規 `sync.ps1` / `sync.sh`(`pull` / `push` / `status` / `lock` / `unlock`)。
- `~/.claude.json`・認証・設定は git ストアに入れない(projects/skills/mcp のみ)。

## 1.2.0
- **対話インストーラ**: `install.ps1` / `install.sh` を引数なしで実行すると、共有するか/コンポーネント/同期フォルダ/フック導入を順に質問して分岐。
- スキルだけ入れて共有しない `-Local` / `--local` を追加。
- `SKILL.md` に「Claude が代行する際の対話フロー」(各分岐でユーザーに確認)を明記。
- **完全バイリンガル文書**(英語 `README.md` + 日本語 `README.ja.md`)、バッジ・言語スイッチャ付き。

## 1.1.0
- **3つの共有コンポーネントを個別 ON/OFF**: `projects` / `skills` / `mcp`(`setup` のフラグ/config で切替)。
- **MCP 共有**(`mcp-sync`): `mcpServers` を `~/.claude.json` と共有ファイル間で export/import(`~/.claude.json` はリンクしない)。書込み前にバックアップ＆検証、`env` の秘密が共有される場合は警告、`--strip-env` で除外可。
- **安全第一の移行**: 破壊的な `link` と MCP `import` は **`-Yes`/`--yes` 無しはドライラン**。明示警告＋自動バックアップ。
- config キーを `shareProjects` / `shareSkills` / `shareMcp` に改称(旧 `linkProjects`/`linkSkills` も読込)。
- インストーラに `-Skills` / `-Mcp` / `-NoProjects` セレクタ追加。

## 1.0.0
- 初回リリース。
- Windows / macOS / Linux で `~/.claude/projects`(任意で `~/.claude/skills`)を任意の同期フォルダ越しに共有。
- config 駆動(`~/.claude/session-sync.local.conf`)・ハードコードなし。
- `setup`(prepare/link/status)、`cc`(ロック付き起動)、`resume-other`(別デバイスの会話取り込み)。
- プロジェクト単位(または global)ロック。
- 任意の自動ロックフック `install-hooks`(SessionStart/SessionEnd)。
- 同期フォルダ自動検出(`detect-sync`)とワンショットインストーラ(`install.ps1` / `install.sh`)。
