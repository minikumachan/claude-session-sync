# 変更履歴 (Changelog)

[English (CHANGELOG.md)](CHANGELOG.md) | **日本語** · 本プロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/) に従います。

> **ひとことで言うと:** Claude Code の会話履歴を複数のパソコンで共有(同期アプリが無ければ GitHub 経由でも)し、
> 同じプロジェクトの同時編集による履歴破損を防ぎ、**`claude -h`** で全履歴を見られるようにする道具です
> (公式の **`claude -r`** はそのまま)。各版の最初の行が平易な要約、続く箇条書きが詳細です。

## 1.16.0
**要約:** デバイス切替時に**作業パスの存在検証＋同期/移行の完了チェック**を追加(競合・転送中・履歴未到達を警告し、未完了状態での無駄なやり直しを防止)。さらに**履歴から再開する際に前回の モデル/思考深度/権限 を引き継ぐ**ように。
- **同期/移行の健全性チェック。** デバイス切替検知時に、共有到達・**この会話の履歴(.jsonl)が当デバイスに届いているか**・履歴/作業フォルダの **同期競合(`*.sync-conflict*`)/転送中(`~syncthing~*` 等)** を高速確認し、問題があれば警告(無駄なトークン消費を回避)。問題なしなら簡潔に「問題なし」。作業パスは**存在確認してから**提示。
- **再開時に前回設定を引き継ぐ。** SessionStart フックが sid→(model/effort/permission) を `<share>/sessions/launchopts.map` に記録(env `CSS_LAUNCH_*` 優先・無ければ stdin の model と既存値を保持)。`claude -h` の再開/フォーク・`boot-launch` の last/resume は、このマップ(+保険として履歴末尾の model)から復元して `--model/--effort/--permission-mode` を付与。権限を項目で明示した場合のみ優先。
- バグ修正: 起動オプション記録の配列結合の不具合(余分なカンマ)を修正。マップ書込はロック付き・UTF-8。

## 1.15.0
**要約:** **権限(permission)の切替**を追加し、モデル/思考深度と合わせて `claude -a`・`claude -h`・新コマンド `/cc-mode` から扱えるように。権限は `plan` から **完全フリー(`--dangerously-skip-permissions`：env 値の取得/コピー/任意実行まで無確認)** まで用意し、上位権限は切替時に警告で再確認します。
- **権限を全面サポート。** `default`/`plan`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`(⚠)/`full`(⚠⚠=完全フリー)。`full` は `--dangerously-skip-permissions`、他は `--permission-mode <値>`。
- **`claude -a`**: 起動項目ごとに モデル/思考深度/**権限**/リモートを設定(項目編集に「権限」行追加・複数項目対応)。**bypassPermissions/full は設定時に y/N 警告**。`install-autostart` に `-Permission`(`--permission`)追加、boot.json に `permission` フィールド。
- **`claude -h`**: 操作メニュー(Tab)に **[r] 権限を変えて再開** を追加。権限ピッカーで選び `--permission-mode`/`--dangerously-skip-permissions` 付きで再開(上位は警告)。
- **`/cc-mode`**(新スキル `skills/cc-mode`、同期対象): セッション中に現在値(モデル/思考深度/権限)と切替手順を表示。恒久切替は公式機構(`/model`・Shift+Tab)で、完全フリー等は起動時指定へ誘導。
- 上位権限は強力なため、警告と再確認を必須化。信頼できる用途のみ。

## 1.14.0
**要約:** **デバイス切替の自動検知**を追加。別の PC で会話を再開する(元のデバイスに戻る場合も含む)と、切り替わったことと**このデバイス用の正しい作業パス**を会話に自動で伝えます。
- **SessionStart フック `hook-devswitch.*`。** 会話ごとに「直近のデバイス + 作業フォルダ」を `<share>/sessions/lastseen.map` に記録し、前回と異なるデバイスでの再開を検知したら、その旨と対応パスを stdout で Claude の文脈に通知(SessionStart は stdout が文脈に入る)。
- **適切な作業パスの推定。** 前回 cwd がローカルに在ればそれ、無ければ**ホーム相対の同一構造**(Win `C:\Users\X\proj` ↔ Mac/Linux `/Users|/home/Y/proj`)をこのデバイスのホーム配下で探して提示。OS でパスが変わっても正しい絶対パスで作業継続。
- `install-hooks` が SessionStart に `hook-devswitch` を追加登録。`claude -a` に「デバイス切替の通知 ON/OFF」トグル、conf `deviceSwitchNotice`(既定 ON)。記録のみで会話本文・秘密は送りません。

## 1.13.0
**要約:** 「スマホからのトリガ起動(ウォッチャ)」を**完全削除**(スマホ→未起動PCの新規起動は公式 Dispatch に一本化)。`claude -a` を**設定ハブ**に刷新し、同期状態の確認・会話タイトル自動更新の ON/OFF・共有の開始/元の履歴先への復元 を追加。`claude -h` の履歴一覧がフォーカス/リサイズで崩れる不具合も修正。
- **remote-watch を撤去。** `remote-watch.{ps1,sh}`・`-Watch`/`remoteWatch`/`remoteWatchDir`・監視フォルダ・常駐登録をすべて削除(設定の痕跡も除去)。スマホからの遠隔起動は公式 **Dispatch**(Claude デスクトップアプリ)を使用。
- **`claude -a` 設定ハブ化。** 自動起動の管理に加え、①同期の状態表示(transport/保存先/projects・skills・mcp)②会話タイトル自動更新 ON/OFF ③共有の開始・再リンク ④MCP 共有 ⑤元の履歴先へ復元 を1画面に。破壊的操作(リンク/復元/取り込み)は安全のため**手順表示**のみ。見やすい ASCII デザイン・カテゴリ分け。
- **`claude -h` のフォーカス/リサイズ崩れを修正。** キー入力を待たずにウィンドウ幅/高さの変化を検知して再描画。

## 1.12.1
**要約:** `claude -a`(自動起動設定メニュー)の表示崩れを修正。日本語環境で枠線がズレる問題と、ウィンドウのリサイズ/フォーカス復帰で崩れたままになる問題を解消。
- **罫線文字をやめ ASCII に。** ヘッダ枠や `❯`・`…` などの East Asian Ambiguous 幅文字(日本語環境で全角描画されてズレる)を使わず、ASCII の見出し/マーカ(`>`)に変更。項目編集のラベルは**表示幅**で揃えてコロンが一直線に。
- **リサイズ/フォーカスで自動再描画。** キー入力を待たずにウィンドウ幅の変化を検知して描き直すので、ウィンドウサイズ変更後も崩れない。

## 1.12.0
**要約:** ログイン自動起動を強化。起動する会話を**複数**登録でき、項目ごとに**モデルと思考深度**を選べます(壁打ちは Sonnet・思考 medium が既定)。**特定の会話を再開する項目はその会話のモデル/深度をそのまま使用**します。
- **複数の起動項目。** `~/.claude/session-sync.boot.json`(配列・デバイス別)に複数項目を保存し、ログオン時にまとめて起動(最後の1件は同じウィンドウ、残りは各々新ウィンドウ)。多重起動チェックは全体で1回。
- **モデル/思考深度。** `new`(壁打ち)項目は `--model`(既定 `sonnet`=最新)と `--effort`(low/medium/high/xhigh/max、既定 `medium`)を指定可能。`last`/`resume`(特定会話)は付けず、会話のものを使用。
- **`claude -a` を一覧マネージャ化。** 項目の追加/編集/削除、種類・モデル・思考深度・リモートの設定が矢印キーで可能(Enter 編集/追加、D 削除、S 保存)。`install-autostart` に `-Model`/`-Effort`/`-Apply`(`--model`/`--effort`/`--apply`)を追加。
- 注: モデルは `claude --model` のエイリアス/ID。`sonnet` は最新 Sonnet を指す(指定 ID も入力可)。

## 1.11.0
**要約:** 自動起動・リモートの設定を **`claude -a`** のワンコマンド対話メニュー(矢印キー操作)にしました。オプションを覚えなくても設定できます。
- **`claude -a` で対話設定。** `claude -h`(履歴ブラウザ)と同じ感覚で、矢印キーだけで「どの会話で起動 / リモート / 多重起動チェック / スマホからの起動」を切り替え、Enter で保存・有効化(Tab=全解除)。「特定の会話を毎回」は直近の会話一覧から選べます(新規 `autostart-ui.{ps1,sh}`)。
- **会話でも設定。** 「自動起動を設定して」と言えば、Claude が確認しながら設定します。
- `install-shell-wrap` が `-a`/`--autostart` も横取りするようになりました(`-h` と同様、`-r` 等は公式のまま)。内部の保存・登録は v1.10.0 の `install-autostart.*` に委譲(挙動は同じ)。

## 1.10.0
**要約:** PC ログイン時の **claude 自動起動**(新規/特定会話の再開・多重起動チェック・リモート可)と、**スマホからのリモート起動**を設定できるようにしました。
- **ログイン自動起動。** `install-autostart`(Windows: `.ps1` / mac・Linux: `.sh`)で、ログイン時に `claude` を自動起動。`bootLaunch=new`(新規)/`last`(最近の会話を再開)/`<sid>`(特定の会話を毎回再開)を選べます。Windows は Startup フォルダの shortcut、mac/Linux は LaunchAgent / `.desktop` autostart で実現(**管理者権限不要**)。
- **多重起動チェック。** 起動前に共有 `locks/` を確認し、**他デバイス**が使用中(12h 以内の有効ロック)なら自動起動を**中止して警告**。Windows と Mac の同時起動による履歴破損(`.sync-conflict`)を防ぎます。
- **起動時リモート ON/OFF。** `bootRemote=true|false|ask`。`true` で `claude --remote-control` 付き起動 → PC が起動していれば**スマホ/claude.ai から常時操作可**。`ask` は起動時に尋ねます(8秒で OFF)。要 Claude Code v2.1.51+ / claude.ai ログイン。
- **スマホからの起動 + 指定履歴で起動。** `remote-watch`(常駐ウォッチャ、`-Watch`/`--watch`)が同期フォルダ `<share>/remote/inbox` を監視し、ファイルが置かれたら `claude --remote-control`(名前/中身に session-id があれば `--resume <sid>` も)を起動。**追加のポート開放・外部公開は不要**(同期フォルダ経由)。起動後は claude アプリ/claude.ai から操作。**PC が起動している間のみ**有効。
- **新スクリプト**: `boot-launch.{ps1,sh}` / `remote-watch.{ps1,sh}` / `install-autostart.{ps1,sh}`。設定は `session-sync.local.conf`(同期しない=デバイス別)に `bootLaunch`/`bootRemote`/`bootCheckMulti`/`remoteWatch`/`remoteWatchDir` として保存。
- **修正**: `setup.ps1` を `-AutoTitle`/`-NoAutoTitle` 無しで再実行するとクラッシュする問題(`OrderedDictionary` に存在しない `.ContainsKey` を呼んでいた)を `.Contains` に修正。

## 1.9.0
**要約:** `claude -h` に**お気に入り**、**会話のフォーク(分岐)**、**文脈を引き継いだ新規会話**を追加(Tab キーの操作メニューから)。
- **★お気に入り＋専用タブ。** 任意の会話をお気に入りに登録し、新タブ `★お気に入り` でまとめて管理(★印表示)。設定は `<share>/sessions/favorites.txt`(＋ローカル控え)に保存され、**全パソコン共通**。
- **会話のフォーク。** Claude 標準の `--fork-session` で会話を複製し**別の分岐**として継続(新しいセッションIDで作成・元は変更しない)。
- **文脈を引き継いで新規。** 選んだ会話の要点(最初の要望＋直近のやり取り)を `--append-system-prompt` で引き継ぎ、**新しい会話**を開始(履歴の全再生ではない)。
- **操作メニューを追加**: 一覧で項目を選び **Tab** キーで *続きから / お気に入り / フォーク / 文脈引き継ぎ新規 / プレビュー*。(一覧での1文字キーは従来どおりライブ検索に使われます。)

## 1.8.0
**要約:** 会話に**内容と言語に合った短いタイトルを自動命名**する機能を追加。作業を進めるとセッション名が分かりやすいタイトルへ自動で改名されます。
- **`Stop` フックで自動命名。** 数ユーザー発話ごと(`titleEvery`、既定5)に、バックグラウンドで会話の冒頭抜粋を軽量モデル(`titleModel`、既定 `haiku`)へ渡して短いタイトルを生成し、`<share>/sessions/titles.map`(共有しない場合は `~/.claude/sessions/titles.map`)へ保存します。`claude -h` はこのタイトルを**最優先**(標準の `ai-title` より上)で表示するので、どのパソコンからも同じ名前で見えます。
- **言語自動。** `titleLang=auto`(既定)は会話の言語でタイトルを書きます。`ja`/`en`/… を指定すれば固定可能。
- **新スクリプト**: `title-gen.{ps1,sh}`(生成本体)と `hook-title.{ps1,sh}`(スロットリング付き Stop フック)。`install-hooks` が従来のロックフックに加えて `Stop` を登録。`setup` に `-AutoTitle`/`-NoAutoTitle`/`-TitleLang`(`--auto-title`/`--no-auto-title`/`--title-lang`)を追加し、`autoTitle`/`titleLang`/`titleModel`/`titleEvery` を保存。
- **安全・きれい。** 送るのは会話の短い抜粋のみで、認証情報は送りません。生成用の一時セッションは専用作業ディレクトリで実行して**自動削除**し、`claude -h` の一覧にも出しません。再入防止に環境変数 `CSS_TITLEGEN` を使用。

## 1.7.5
**要約:** `claude -h` の検索ボックスの右端がずれる問題を修正しました。
- 上枠の長さを**文字数**で計算していたため、全角文字(🔍アイコンや日本語ラベル/入力は表示2桁)で右上の角が下枠とずれていました。枠線と余白を**表示幅**(全角CJK/絵文字=2桁)で計算するようにし、検索欄に全角文字を入力しても枠が崩れません。Windows(`SetCursorPosition`描画)・Mac/Linux(curses、`unicodedata`使用)の両方で修正。

## 1.7.4
**要約:** `claude -h` で ↑/↓ を押すたびに画面全体が再描画されてちらつく問題を解消。ハイライトだけが移動します。
- **矢印移動のちらつきを解消(Windows)。** 選択移動時は画面を消去して全再描画する代わりに、**変化する2行(旧選択行・新選択行)だけをその場で書き換え**。全再描画はタブ切替・検索・ページ送り・プレビュー復帰など実際に表示が変わるときだけに限定。
- Mac/Linux は元々ちらつかない描画(curses の差分更新)のため変更なし。

## 1.7.3
**要約:** `claude -h` で項目を移動したときのロード(まだ見ていない履歴へ移ると一瞬止まる現象)を解消し、操作を滑らかにしました。
- **読み込みを高速化＋上限付きに。** 各項目のタイトル/デバイス/件数を、ファイル全体ではなく**行数上限つきの高速スキャン**(JSON解析は必要な行だけ)で取得。74MB の履歴で初回スキャンが約560ms→約80ms に短縮。
- 非常に大きい履歴は件数を全行数えずに `4000+` のように表示(打ち切り)。結果はキャッシュされるので、一度見た項目への再訪は瞬時です。

## 1.7.2
**要約:** `claude -h` の上部に検索ボックス(入力で即フィルタ)を追加し、各項目を見やすい2行表示にしました。
- **枠付き検索ボックス**を最上部に。文字を打つだけで即フィルタ、Backspace で消去、Esc でクリア(空なら終了)。
- **各項目は2行＋区切り線**:1行目=タイトル、2行目=*デバイス・メッセージ件数・時刻・プロジェクト*。一覧が見やすい。
- **Space** で内容プレビュー、**Enter** で再開。

## 1.7.1
**要約:** `claude -h` の画面を、公式 `claude -r` の見た目・操作感に寄せて作り直しました。
- `❯` キャレット＋選択行ハイライト。列は **タイトル ・ 相対時刻(「2時間前」)・ メッセージ件数 ・ 由来デバイス**(色ラベル)。
- 上部にタブバーと区切り線、下部にキーヒント行 — 公式のレイアウトに合わせています。
- **Space** で内容プレビュー、**Enter** で再開、`/` で検索、`q`/Esc で終了。(Mac/Linux はマウスも)

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
