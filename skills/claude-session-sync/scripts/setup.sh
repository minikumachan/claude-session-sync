#!/usr/bin/env bash
#  claude-session-sync : setup / link / status  (macOS / Linux)
set -euo pipefail
CLAUDE="$HOME/.claude"
CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- || true; }

SHARE=""; WITH_SKILLS=0; LOCKSCOPE="project"; PHASE="all"; STATUS=0
while [[ $# -gt 0 ]]; do case "$1" in
  --share) SHARE="$2"; shift 2;;
  --with-skills) WITH_SKILLS=1; shift;;
  --lock-scope) LOCKSCOPE="$2"; shift 2;;
  --phase) PHASE="$2"; shift 2;;
  --status) STATUS=1; shift;;
  *) echo "不明な引数: $1" >&2; shift;;
esac; done

if [[ $STATUS -eq 1 ]]; then
  echo "=== session-sync 状態 ($(uname -s)) ==="
  echo "config: $CFG (存在=$([[ -f $CFG ]] && echo yes || echo no))"
  [[ -f "$CFG" ]] && sed 's/^/  /' "$CFG"
  for n in projects skills; do
    p="$CLAUDE/$n"
    if [[ -L "$p" ]]; then echo "  ~/.claude/$n -> $(readlink "$p")"
    elif [[ -e "$p" ]]; then echo "  ~/.claude/$n: 実フォルダ(未リンク)"; fi
  done
  if [[ -n "$(get share)" ]]; then for f in "$(get share)"/locks/*.lock; do [[ -e "$f" ]] && echo "  lock $(basename "$f"): $(cat "$f")"; done; fi
  exit 0
fi

[[ -z "$SHARE" ]] && SHARE="$(get share)"
[[ -z "$SHARE" ]] && { echo "共有フォルダ指定が必要:  setup.sh --share '<.../_ClaudeCode>'" >&2; exit 1; }
SHARE="${SHARE%/}"

[[ "$(get linkSkills)" == "true" ]] && WITH_SKILLS=1
mkdir -p "$SHARE/sessions/projects" "$SHARE/locks" "$SHARE/exports"
[[ $WITH_SKILLS -eq 1 ]] && mkdir -p "$SHARE/skills"

{
  echo "share=$SHARE"
  echo "linkProjects=true"
  echo "linkSkills=$([[ $WITH_SKILLS -eq 1 ]] && echo true || echo false)"
  echo "lockScope=$LOCKSCOPE"
} > "$CFG"
echo "✔ config 保存: $CFG"

names=(projects); [[ $WITH_SKILLS -eq 1 ]] && names+=(skills)
tgt_of(){ case "$1" in projects) echo "$SHARE/sessions/projects";; skills) echo "$SHARE/skills";; esac; }

if [[ "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  for n in "${names[@]}"; do
    lp="$CLAUDE/$n"; tg="$(tgt_of "$n")"
    if [[ -d "$lp" && ! -L "$lp" ]]; then
      stamp="$(date +%Y%m%d_%H%M%S)"
      cp -a "$lp" "${lp}_backup_$stamp"
      echo "✔ バックアップ: ${n}_backup_$stamp"
      cp -an "$lp"/. "$tg"/ 2>/dev/null || true   # local -> share (新規のみ)
      cp -an "$tg"/. "$lp"/ 2>/dev/null || true   # share -> local (新規のみ)
      echo "✔ $n を非破壊マージ"
    fi
  done
fi

if [[ "$PHASE" == "link" || "$PHASE" == "all" ]]; then
  for n in "${names[@]}"; do
    lp="$CLAUDE/$n"; tg="$(tgt_of "$n")"
    if [[ -L "$lp" ]]; then echo "• $n は既にリンク済み ($(readlink "$lp"))"; continue; fi
    [[ -e "$lp" ]] && mv "$lp" "${lp}_local_old"
    ln -s "$tg" "$lp"
    echo "✔ $n -> $(readlink "$lp")"
  done
fi

chmod +x "$DIR"/*.sh 2>/dev/null || true
echo "完了。起動は cc.sh、別デバイス会話の取り込みは resume-other.sh。"
