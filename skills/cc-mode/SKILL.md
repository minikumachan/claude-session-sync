---
name: cc-mode
description: モデル / 思考深度(effort) / 権限(permission) の現在値と切り替え方法を表示する操作リファレンス。claude-session-sync 用。「モデル変更」「思考深度」「権限」「bypass」「完全フリー」等で使う。
disable-model-invocation: true
user-invocable: true
argument-hint: "[model] [effort] [permission]"
---
あなた(Claude)は、以下を**ユーザー向けに簡潔な一覧として表示**してください。実際の切り替えはユーザー操作が必要なので、勝手に実行せず、方法を案内します。引数は `モデル=$0 / 思考深度=$1 / 権限=$2`(空欄は変更なし)。

# モデル / 思考深度 / 権限 の切替（claude -a / claude -h と連動）

- 現在の思考深度(effort): **${CLAUDE_EFFORT}**
- 要求された値: モデル=`$0` / 思考深度=`$1` / 権限=`$2`

## セッション中に変える（公式の操作）
- **モデル**: `/model $0`（例 `/model opus`）。引数なしの `/model` でメニュー。これはセッション中に恒久的に切り替わります。
- **思考深度(effort)**: low / medium / high / xhigh / max。起動時に固定するには `claude -a`(自動起動の各項目)か `claude -h` の権限付き再開で指定。
- **権限(permission)**: **Shift+Tab** でモードを循環（default / acceptEdits / plan など）。
  - **bypassPermissions** や **完全フリー（`--dangerously-skip-permissions`：env 値の取得・コピー・任意コマンド実行まで無確認）** はセッション中の昇格ではなく、起動時に指定します。

## 起動時にまとめて指定（推奨：3項目すべて切替可能）
- **`claude -a`** … 自動起動する各会話に「モデル / 思考深度 / 権限」を保存（上位権限は設定時に警告再確認）。
- **`claude -h`** … 一覧で **Tab → [r] 権限を変えて再開**（plan〜完全フリー、上位は警告）。

> 注意: 完全フリー権限は強力です。信頼できる作業のみで使用してください。
