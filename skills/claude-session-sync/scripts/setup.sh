#!/usr/bin/env bash
#  claude-session-sync : setup / link / status  (macOS / Linux)
#  3 components, each ON/OFF: projects, skills (symlink) / mcp (file sync via mcp-sync.sh).
#  Destructive `link` phase is a dry-run unless --yes is given.
set -euo pipefail
CLAUDE="$HOME/.claude"
CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- || true; }
asbool(){ local v="$1" def="$2"; [[ -z "$v" ]] && { echo "$def"; return; }; [[ "$v" == "true" ]] && echo true || echo false; }
onoff(){ [[ "$1" == "true" ]] && echo ON || echo OFF; }

SHARE=""; LOCKSCOPE=""; PHASE="all"; STATUS=0; YES=0
P_SET=""; S_SET=""; M_SET=""
while [[ $# -gt 0 ]]; do case "$1" in
  --share) SHARE="$2"; shift 2;;
  --projects) P_SET=true; shift;;     --no-projects) P_SET=false; shift;;
  --skills) S_SET=true; shift;;       --no-skills) S_SET=false; shift;;
  --mcp) M_SET=true; shift;;          --no-mcp) M_SET=false; shift;;
  --lock-scope) LOCKSCOPE="$2"; shift 2;;
  --phase) PHASE="$2"; shift 2;;
  --status) STATUS=1; shift;;
  --yes) YES=1; shift;;
  *) echo "不明な引数: $1" >&2; shift;;
esac; done

COMP_P="${P_SET:-$(asbool "$(get shareProjects)" "$(asbool "$(get linkProjects)" true)")}"
COMP_S="${S_SET:-$(asbool "$(get shareSkills)"   "$(asbool "$(get linkSkills)" false)")}"
COMP_M="${M_SET:-$(asbool "$(get shareMcp)" false)}"
[[ -z "$LOCKSCOPE" ]] && LOCKSCOPE="$(get lockScope)"; [[ -z "$LOCKSCOPE" ]] && LOCKSCOPE=project

if [[ $STATUS -eq 1 || "$PHASE" == "status" ]]; then
  echo "=== session-sync 状態 ($(uname -s)) ==="
  echo "config: $CFG (存在=$([[ -f $CFG ]] && echo yes || echo no))"
  echo "共有コンポーネント:  projects=$(onoff "$COMP_P")  skills=$(onoff "$COMP_S")  mcp=$(onoff "$COMP_M")  (lockScope=$LOCKSCOPE)"
  echo "share: $(get share)"
  for n in projects skills; do
    p="$CLAUDE/$n"
    if [[ -L "$p" ]]; then echo "  ~/.claude/$n -> $(readlink "$p")"; elif [[ -e "$p" ]]; then echo "  ~/.claude/$n: 実フォルダ(未リンク)"; fi
  done
  s="$(get share)"; [[ -n "$s" ]] && echo "  MCP共有ファイル: $s/mcp/servers.json  存在=$([[ -f "$s/mcp/servers.json" ]] && echo yes || echo no)"
  exit 0
fi

[[ -z "$SHARE" ]] && SHARE="$(get share)"
[[ -z "$SHARE" ]] && { echo "共有フォルダ指定が必要:  setup.sh --share '<.../_ClaudeCode>'" >&2; exit 1; }
SHARE="${SHARE%/}"

mkdir -p "$SHARE/sessions/projects" "$SHARE/locks" "$SHARE/exports"
[[ "$COMP_S" == "true" ]] && mkdir -p "$SHARE/skills"
[[ "$COMP_M" == "true" ]] && mkdir -p "$SHARE/mcp"

{
  echo "share=$SHARE"
  echo "shareProjects=$COMP_P"
  echo "shareSkills=$COMP_S"
  echo "shareMcp=$COMP_M"
  echo "lockScope=$LOCKSCOPE"
} > "$CFG"
echo "✔ config 保存: projects=$(onoff "$COMP_P") skills=$(onoff "$COMP_S") mcp=$(onoff "$COMP_M")"

names=(); [[ "$COMP_P" == "true" ]] && names+=(projects); [[ "$COMP_S" == "true" ]] && names+=(skills)
tgt_of(){ case "$1" in projects) echo "$SHARE/sessions/projects";; skills) echo "$SHARE/skills";; esac; }

if [[ "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  for n in "${names[@]}"; do
    lp="$CLAUDE/$n"; tg="$(tgt_of "$n")"
    if [[ -d "$lp" && ! -L "$lp" ]]; then
      stamp="$(date +%Y%m%d_%H%M%S)"; cp -a "$lp" "${lp}_backup_$stamp"
      echo "✔ バックアップ: ${n}_backup_$stamp"
      cp -an "$lp"/. "$tg"/ 2>/dev/null || true
      cp -an "$tg"/. "$lp"/ 2>/dev/null || true
      echo "✔ $n を非破壊マージ"
    fi
  done
fi

if [[ "$PHASE" == "link" || "$PHASE" == "all" ]]; then
  todo=()
  for n in "${names[@]}"; do
    lp="$CLAUDE/$n"
    if [[ -L "$lp" ]]; then echo "• $n は既にリンク済み ($(readlink "$lp"))"; else todo+=("$n"); fi
  done
  if [[ ${#todo[@]} -gt 0 ]]; then
    echo
    echo "⚠⚠ 破壊的な操作の確認 ⚠⚠"
    echo "次の各フォルダを退避(*_local_old)し、共有先へのシンボリックリンクに置き換えます: ${todo[*]}"
    echo "・実行前に Claude Code を完全終了してください。"
    echo "・元データは *_backup_<時刻> と *_local_old に保持されます(削除しません)。"
    if [[ $YES -ne 1 ]]; then
      echo "→ これはドライランです。実際に変更するには --yes を付けて再実行してください。"
    else
      for n in "${todo[@]}"; do
        lp="$CLAUDE/$n"; tg="$(tgt_of "$n")"
        [[ -e "$lp" ]] && mv "$lp" "${lp}_local_old"
        ln -s "$tg" "$lp"
        echo "✔ $n -> $(readlink "$lp")"
      done
    fi
  fi
fi

if [[ "$COMP_M" == "true" ]]; then
  echo
  echo "ℹ MCP 共有は ON。~/.claude.json はリンクせず、定義ファイルの同期で行います:"
  echo "   ローカル定義を共有へ:  bash mcp-sync.sh --export"
  echo "   共有定義を取り込み  :  bash mcp-sync.sh --import --yes   (~/.claude.json を変更。要確認)"
  echo "   ⚠ MCP定義の env に秘密が含まれる場合、共有フォルダに保存される点に注意。"
fi
chmod +x "$DIR"/*.sh 2>/dev/null || true
echo "完了。起動は cc.sh / 取り込みは resume-other.sh。"
