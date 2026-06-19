---
name: claude-session-sync
description: >
  Claude Code の会話履歴(projects)・スキル(skills)・MCPサーバ定義(mcp)を複数マシン間で共有/同期する。
  同期方式(transport)は2つ: folder(任意の同期フォルダに依存)/ git(外部同期アプリ不要・自己完結。
  履歴を git remote と push/pull)。
  3コンポーネントはそれぞれ独立に ON/OFF 可能。同セッション(同プロジェクト)の同時アクセスを
  ロックで防ぐ。Windows / macOS / Linux 対応。別デバイスで始めた会話の取り込み再開も行う。
  会話タイトルを内容・言語に合わせて自動命名する機能(Stop フック)もある。
  PC ログイン時の claude 自動起動(複数会話・項目ごとにモデル/思考深度/権限/リモート・多重起動チェック)を
  `claude -a` の設定メニューから管理できる(同期状態の確認・会話タイトル自動更新やデバイス切替通知の ON/OFF・共有の開始/復元も)。
  モデル/思考深度/権限は `claude -h` の起動時や `/cc-mode` でも切替可。権限は plan〜完全フリー(--dangerously-skip-permissions)まで(上位は警告)。
  「会話履歴やスキルやMCPを別PCと共有/同期したい」「別マシンの会話の続きをしたい」
  「同時起動を防ぎたい」「ロック付きで安全に claude を起動したい」
  「会話タイトルを内容に合わせて自動で付けたい/改名したい」
  「PC起動時に自動で claude を立ち上げたい」「スマホからPCの claude を起動/操作したい」ときに使う。
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
`autoTitle=true|false`(会話タイトル自動命名)/ `titleLang=auto|ja|en|…`(auto=会話の言語)/ `titleModel=haiku`(生成モデル)/ `titleEvery=5`(何ユーザー発話ごとに更新)
`bootCheckMulti=true|false`(ログオン自動起動前の他デバイス使用中チェック)/ `deviceSwitchNotice=true|false`(別デバイスでの再開を検知して文脈に通知。既定 ON)。ログオン自動起動する会話の一覧(種類/モデル/思考深度/リモート)は `~/.claude/session-sync.boot.json`(配列・非同期=デバイス別)に保存(旧 `bootLaunch`/`bootRemote` 単一キーは後方互換のみ)

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
  - **タブ式**: `[このプロジェクト(公式-rと同じパス依存)]` `[全履歴(全デバイス)]` `[最近7日]` `[★お気に入り]`。←→ でタブ切替。
  - **ページ式・遅延読込**: 表示中の行だけ内容を読むので、大量でも高速・安定(ページを送るたびに先を読む)。PageUp/PageDown。
  - **上部に枠付き検索ボックス**(文字入力で即フィルタ)。各項目は **2行(タイトル/メタ)＋区切り線** で表示。
  - 操作: 文字入力=検索 / Backspace=消去 / Esc=クリア(空なら終了)/ ↑↓ 選択 / ←→ タブ / PageUp,PageDown ページ / Enter 再開(現フォルダへ取り込み→`claude --resume`)/ Space 内容プレビュー / **Tab=操作メニュー**。
    mac/Linux(curses)は**マウスのホイール/クリック**にも対応。Windows はキーボード操作。
  - **Tab の操作メニュー**(選択項目に対して):
    - **★ お気に入り 追加/解除**: `<share>/sessions/favorites.txt`(共有先優先・無ければ `~/.claude/sessions/favorites.txt`、両方へ保存=全デバイス共通)に sid を記録。一覧では ★ 印、`[★お気に入り]` タブで一覧。
    - **フォーク(分岐)**: 取り込み後 `claude --resume <sid> --fork-session`。**新しいセッションID**で複製され、元の会話は変更されない(別系統で続けられる)。
    - **文脈を引き継いで新規**: 会話の「最初の要望＋直近のやり取り」を文脈として組み立て、`claude --append-system-prompt <文脈>` で**新規会話**を開始(履歴の再生ではなく、要点だけ引き継ぐ)。
  - 各行に**由来デバイスを色＋ラベル**表示(`Win/<user>` `Mac/<user>` `Linux/<user>`。**同機種**は `deviceName`/`devices.map` で識別)。
    **タイトル**の優先順位: `titles.map`(自動命名/後述5b)> Claude の `ai-title` > 冒頭発話。
  - **アクセス中(使用中)の表示・保護**: 共有 `locks/` の有効ロック(`session=<sid>`、12h以内)を読み、該当会話のメタ行に **「● アクセス中: <デバイス>」**(赤)を表示。**操作しなくても数秒ごとに自動更新(ライブ)**=別デバイスで開始/終了すると点灯/消灯が反映(クロスデバイスは**同期(Syncthing等)の遅延ぶんだけ遅れる“ほぼリアルタイム”**。ファイル同期方式の下限)。**使用中の会話を開こうとすると警告して中止**し、「先にそのデバイス側で終了(切断)してから開き直す」よう促す(同時アクセス=`.sync-conflict` 破損の防止)。どうしても開くなら **F で強行**(危険)。resume/フォーク/権限変更で起動に共通。
- 導入/解除: `install-shell-wrap.ps1` /（Unix）`install-shell-wrap.sh`(プロファイル/rc に `claude` 関数を追加。**`-h`=履歴UI / `-a`=自動起動・リモート設定**を横取り、`-r` 含む他は公式へ素通し)。解除 `-Uninstall` / `--uninstall`。
- デバイス名は `setup -DeviceName <名>`(/ `--device-name`)で設定(既定=ホスト名。フックが起動時に `devices.map` へ記録)。

### 4. MCP 共有(mcp が ON のとき)
`~/.claude.json` はリンクせず、`mcpServers` だけを同期する。
- 状態: `mcp-sync.ps1 -Status` / `mcp-sync.sh --status`
- 共有へ出す: `mcp-sync.ps1 -Export`(env に秘密があれば `-Yes` か `-StripEnv` が必要)
- 取り込む(破壊的): `mcp-sync.ps1 -Import -Yes` / `mcp-sync.sh --import --yes`(自動バックアップ＋検証)
- 安全のため PowerShell 7+(pwsh)/ python3 を使用(単一要素配列の破壊を防止)。

### 5. 自動ロック + 自動タイトル + デバイス切替通知(任意・フック)
`install-hooks.ps1` / `install-hooks.sh` で SessionStart(ロック取得 + デバイス切替検知)/SessionEnd(解除)/**Stop**(タイトル)フックを `~/.claude/settings.json` に追加する。
通常の `claude` 起動で自動ロック/解除され(競合時は警告を注入)、**応答完了(Stop)ごとに会話タイトルが自動更新**され、**別デバイスでの再開を検知して文脈へ通知**する(下記5c)。解除 `-Uninstall`/`--uninstall`。

#### 5b. 会話タイトルの自動命名(規則)
Stop フック `hook-title.*` が `titleEvery`(既定5)ユーザー発話ごとに `title-gen.*` を**非同期**起動し、
会話の要点を `claude -p`(既定 `haiku`)に渡して短いタイトルを生成、`<share>/sessions/titles.map`(共有先が無ければ `~/.claude/sessions/titles.map`)へ `sessionId<TAB>title` で保存する。`claude -h` が最優先で表示。
- **命名規則**: 1行・前後の引用符や記号なし・末尾句点なし・約4〜8語/最大~40字・具体的な作業/話題を表す・**会話の言語**(`titleLang=auto`)または `titleLang` 指定言語で記述。
- 設定: `setup.ps1 -AutoTitle|-NoAutoTitle [-TitleLang auto|ja|en|…]`(/ `--auto-title|--no-auto-title --title-lang …`)。`titleModel`/`titleEvery` は conf で調整。
- 生成用の一時セッションは専用作業ディレクトリで実行し**自動削除**(`claude -h` の一覧にも出さない)。再入防止に環境変数 `CSS_TITLEGEN` を使用。秘密情報は送らない(会話本文の冒頭抜粋のみ)。

#### 5c. デバイス切替の検知・通知(`hook-devswitch.*`)
SessionStart フック `hook-devswitch.*` が、会話 sid ごとに「直近に使ったデバイス + 作業フォルダ」を `<share>/sessions/lastseen.map`(共有先優先)へ記録する。再開時、**前回と異なるデバイス**(元のデバイスへ戻った場合も含む)を検知したら、その旨と**このデバイスでの対応する作業パス**を **stdout に出力して Claude の文脈へ通知**する(SessionStart は stdout がそのまま文脈に入る)。
- **適切な作業パスの推定+存在検証**: 前回 cwd がローカルに在ればそれ、無ければ**ホーム相対の同一構造**(例 `C:\Users\X\proj` ↔ `/Users/Y/proj`)をこのデバイスのホーム配下で探し、**存在を確認してから**提示。見つからなければ現在地を使うよう促す(誤ったパスでの作業=無駄なやり直しを防ぐ)。
- **同期/移行の健全性チェック(高速)**: 共有フォルダ到達・**この会話の履歴(.jsonl)が当デバイスに届いているか**・履歴/作業フォルダの **同期競合(`*.sync-conflict*`)や転送中(`~syncthing~*` 等)** を簡潔に確認し、問題があれば**警告して重複作業・誤編集を避ける**よう伝える(無駄なトークン消費の防止)。問題なしなら「問題は検出されず」と短く返す。
- **再開時に前回の モデル/思考深度/権限 を引き継ぐ**: フックは起動時に sid→(model/effort/permission) を `<share>/sessions/launchopts.map` に記録(env `CSS_LAUNCH_MODEL/EFFORT/PERM` 優先、無ければ stdin の model と既存値を保持)。`claude -h` 再開/フォーク・`boot-launch` の last/resume は、このマップ(+保険として履歴末尾の model)から**前回値を復元して `--model/--effort/--permission-mode` を付与**する。権限を項目で明示した場合のみそれを優先。
- これにより、OS でパス表記が変わっても Claude が**このデバイスの正しい絶対パス**で作業でき、デバイス切替の事実・同期完了状況・前回の動作設定が一貫する。
- 設定: `claude -a` の「デバイス切替の通知」トグル、または conf `deviceSwitchNotice=true|false`(既定 ON)。記録のみで会話本文や秘密情報は送らない。

### 6. 状態確認 / ロールバック
- 状態: `setup.ps1 -Status` / `setup.sh --status`(各コンポーネントON/OFF・リンク状態・MCP・ロック)
- ロールバック(リンクのみ削除、実体は同期フォルダに残る):
  - Windows: `Remove-Item ~/.claude/projects; Rename-Item ~/.claude/projects_local_old projects`
  - Unix: `rm ~/.claude/projects; mv ~/.claude/projects_local_old ~/.claude/projects`
  - MCP は `~/.claude.json.bak_<時刻>` から復元。

### 7. 設定メニュー `claude -a`(ログオン自動起動 / 同期 / 復元)
`install-shell-wrap` 導入時、**`claude -a`** で設定ハブ(`autostart-ui.{ps1,sh}`)が開く。描画は ASCII のみ・リサイズ/フォーカスで自動再描画(日本語環境でも崩れない)。扱える項目:
- **自動起動する会話を管理**(複数可・項目ごとに**モデル/思考深度/権限/リモート**)
- **会話タイトルの自動更新 ON/OFF**(`autoTitle` を即時トグル)
- **デバイス切替の通知 ON/OFF**(`deviceSwitchNotice`、別デバイスでの再開検知=5c)
- **同期の状態を表示**(transport・保存先・projects/skills/mcp の共有状態 = `setup -Status`)
- **共有を開始/再リンク・MCP共有・元の履歴先へ復元**(すべてメニュー上のテキストGUIで操作・**その場で実行**。コマンド文字列は出さない。破壊的操作は予行演習や警告＋y/N 確認を挟む)

ログオン自動起動の詳細:
- 起動項目は `~/.claude/session-sync.boot.json`(配列・非同期=デバイス別)、共通設定 `bootCheckMulti` は `session-sync.local.conf`。管理者権限不要・次回ログオンから有効。
- 項目の種類: `new`(壁打ち)…新規会話。**モデル**(`--model`, 既定 `sonnet`=最新)と**思考深度**(`--effort low|medium|high|xhigh|max`, 既定 `medium`)を指定可。 `last`/`resume`(特定会話)…再開。**モデル/思考深度は付けず会話のものを使用**。
- **権限(全種類で指定可)**: `default`(都度確認)/`plan`(読取中心)/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`(⚠)/`full`(⚠⚠ `--dangerously-skip-permissions`=全チェック回避・env 値の取得/コピー/任意実行まで無確認)。それ以外は `--permission-mode <値>`。**上位権限(bypassPermissions/full)は設定時に警告再確認**を挟む。
- **多重起動チェック**(`bootCheckMulti`): 起動前に共有 `locks/` の**他デバイス**有効ロック(12h以内)を検知したら**全起動を中止**して警告(Win/Mac 同時起動=履歴破損を防止)。
- **リモート**: 項目の `remote=true` で `claude --remote-control` 付き起動 → スマホ/claude.ai から接続・操作(要 v2.1.51+ / claude.ai ログイン Pro/Max)。`ask` は起動時に尋ねる。
- **会話で設定**: ユーザーが「自動起動を設定して」等と言ったら、希望(起動する会話と数・各モデル/思考深度/権限・リモート・多重起動チェック)を確認し `install-autostart.*` か `claude -a` で反映。
- **コマンド直接**: `install-autostart.ps1 -Launch new [-Model sonnet] [-Effort medium] [-Permission bypassPermissions|full|…] | -Launch last | -Session <sid> [-RemoteMode ask] / -Apply / -Status / -Uninstall`(sh は `--launch/--model/--effort/--permission/--session/--apply/--status/--uninstall`、JSON は python3)。
- **`claude -h` から権限を変えて起動**: 一覧で Tab → **[r] 権限を変えて再開**(plan〜完全フリー。上位は警告再確認)→ `claude --resume <sid> --permission-mode …` / `--dangerously-skip-permissions`。
- **セッション中の切替** — `/cc-mode [model] [effort] [permission]`(別スキル `skills/cc-mode`、同期対象): 現在値と切替手順を表示。恒久切替できるのは公式機構(**モデル=`/model`**、**権限=Shift+Tab** で循環)で、`bypassPermissions`/完全フリーは `claude -h`[r] か `claude -a` で起動時指定。
- 実装: Windows は Startup フォルダの shortcut(`ClaudeSessionSync-Boot.lnk`)、mac/Linux は LaunchAgent(`com.claude-session-sync.boot`)/ `~/.config/autostart` の `.desktop`。
- **スマホから“未起動のPCで新規セッション”を起動**したい場合は公式 **Dispatch**(Claude デスクトップアプリ+スマホアプリのペアリング、要 Pro/Max)を使う。本スキルに専用機能は持たない。

### 補助
- `detect-sync.*`: 同期フォルダ候補の検出。 `hook-lock.*` / `hook-title.*` / `title-gen.*` / `hook-devswitch.*`: フック本体(直接呼ばない)。 `boot-launch.*`: 自動起動本体(直接呼ばない)。 `autostart-ui.*`: `claude -a` の設定メニュー本体。
- リポジトリ直下 `install.ps1` / `install.sh`: 配置→検出→prepare→(任意)フックの一括導入。

## パス符号化(再開の注意)
履歴は `projects/<cwdを「英数字以外を-」に符号化した名前>/<id>.jsonl`。OS でフォルダ名が変わるため
`claude --resume`(=`claude -r`)は他OS/他フォルダの会話を自動表示しない → **`claude -h` で全履歴から選び Enter**(現フォルダへ取り込んで `claude --resume`)で続きから再開する。

## スマホ等からのリモート操作
OSをまたいだ同一会話の自動再開は不可。外出先からは Claude Code の **Remote Control**
(`claude --remote-control`、要 v2.1.51+ / claude.ai ログイン)で PC のセッションをスマホ/claude.ai から操作する。
本スキルの **7. ログイン自動起動 + リモート起動**(`install-autostart.*`)で、ログイン時に常時リモート ON にしたり、
スマホから同期フォルダへトリガを置いて `claude --remote-control` を起動(指定会話の再開も可)できる。いずれも **PC が起動している間のみ**有効。

## 安全メモ
- 破壊的操作の前に必ずバックアップ。マージは既存を上書きしない union 方式。
- 同期側の **File Versioning**(Syncthing 等)を有効化すると実質バックアップになる。
- 不明点があれば実行せずユーザーに確認する。
