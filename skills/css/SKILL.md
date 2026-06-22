---
name: css
description: claude-session-sync の会話内コマンド。同期 / 知識アーカイブ / リモート / 基本言語の状態を CLI 風ボックスで表示し、短いサブコマンドで設定変更(新セッションから反映)。停止必須(共有・再リンク・復元・MCP取込)は会話中は不可と表示。/css gui で設定GUI、/css history で履歴UIを別ウィンドウで開く。「設定」「状態」「アーカイブ」「リモート」「css」等で使う。
disable-model-invocation: true
user-invocable: true
argument-hint: "[status|archive on|off|remote all|items|remote c|cfp|ch|cc on|off|lang <code>|autotitle on|off|devnotice on|off|doctor|mcp|gui|history]"
---
ユーザーが claude 会話内で `/css $0 $1 $2` を実行しました。これは会話内操作パネルです。次の手順を**そのまま**実行してください(あなたの判断で設定を変えたり、出力を要約・装飾したりしない。変更はユーザーが打ったサブコマンドだけが行う)。

1. OS を判定し、claude-session-sync の会話内ディスパッチャを**ユーザーの引数そのまま**で1回だけ実行する:
   - **Windows**: `pwsh` があれば `pwsh -NoProfile -File "<HOME>\.claude\skills\claude-session-sync\scripts\css-cmd.ps1" $0 $1 $2`、無ければ `powershell` で同様に。`<HOME>` は `%USERPROFILE%`。
   - **macOS / Linux**: `bash "$HOME/.claude/skills/claude-session-sync/scripts/css-cmd.sh" $0 $1 $2`
   - 引数 `$0 $1 $2` のうち空のものは渡さない(無引数なら status 扱い)。
2. その**標準出力をそのまま**、フェンス付きコードブロック(``` で囲む)に入れて表示する。CLI 風ボックス(╭─ │ ╰─)の体裁・桁を崩さないよう、改変・要約・色付け・追記をしない。
3. 解説は付けない(必要でも1〜2行まで)。`/css gui` や `/css history` を実行した場合は、別ウィンドウが開いた旨のスクリプト出力をそのまま見せるだけでよい。

利用可能サブコマンド(詳細はパネル下部に表示される):
- 表示: `status`(既定) / `help`
- 変更(新セッションから反映): `archive on|off` / `remote all|items` / `remote c|cfp|ch|cc on|off` / `lang <code>` / `autotitle on|off` / `devnotice on|off`
- 確認: `doctor`(必要環境) / `mcp`(MCP 状態)
- GUI(別ウィンドウ・矢印操作): `gui`(claude -a 設定) / `history`(claude -h 履歴)
- 停止必須=会話中は不可(案内のみ表示): `share` / `restore` / `mcp-import`
