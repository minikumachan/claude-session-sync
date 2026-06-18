#!/usr/bin/env bash
#  claude-session-sync : 全パス・全デバイスの履歴を native `claude --resume` で選べるようにする (macOS / Linux)
#  全 .jsonl を「同期しないローカル集約フォルダ」へハードリンクで集め、そこを cwd にして claude --resume を起動。
#    resume-all.sh            # 全履歴の resume ピッカー
#    resume-all.sh --dry-run  # 集約のみ(検証用)
set -uo pipefail
DRY=0; [[ "${1:-}" == "--dry-run" ]] && { DRY=1; shift; }
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
encode(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
HUB="$CLAUDE/all-history"; mkdir -p "$HUB"
ENC="$(encode "$HUB")"; AGG="$PROJECTS/$ENC"; mkdir -p "$AGG"

TRANSPORT="$(get transport)"; STORE="$(get store)"; SHARE="$(get share)"
realBase=""; if [[ "$TRANSPORT" == "git" && -n "$STORE" ]]; then realBase="$STORE"; elif [[ -n "$SHARE" ]]; then realBase="$SHARE"; fi
if [[ -n "$realBase" ]]; then
  realAgg="$realBase/sessions/projects/$ENC"
  d="$realBase"; stroot=""
  while [[ -n "$d" && "$d" != "/" ]]; do [[ -e "$d/.stfolder" ]] && { stroot="$d"; break; }; d="$(dirname "$d")"; done
  if [[ -n "$stroot" ]]; then
    rel="${realAgg#$stroot/}"; sti="$stroot/.stignore"; touch "$sti"
    grep -qxF "/$rel" "$sti" || echo "/$rel" >> "$sti"
  fi
  if [[ "$TRANSPORT" == "git" && -n "$STORE" ]]; then
    gi="$STORE/.gitignore"; touch "$gi"; rel2="${realAgg#$STORE/}"
    grep -qxF "$rel2" "$gi" || echo "$rel2" >> "$gi"
  fi
fi

find "$AGG" -maxdepth 1 -name '*.jsonl' -delete 2>/dev/null || true
n=0
while IFS= read -r -d '' f; do
  case "$f" in "$AGG"/*) continue;; esac
  d="$(basename "$(dirname "$f")")"; b="$(basename "$f" .jsonl)"
  case "$d" in subagents|wf_*) continue;; esac
  case "$b" in agent-*|journal) continue;; esac
  dest="$AGG/$(basename "$f")"
  [[ -e "$dest" ]] || ln "$f" "$dest" 2>/dev/null || cp "$f" "$dest"
  n=$((n+1))
done < <(find "$PROJECTS" -name '*.jsonl' -print0 2>/dev/null)
echo "✔ 全 $n セッションを集約(全パス・全デバイス)。"
[[ $DRY -eq 1 ]] && { echo "[DryRun] $AGG"; exit 0; }
command -v claude >/dev/null 2>&1 || { find "$AGG" -maxdepth 1 -name '*.jsonl' -delete 2>/dev/null; echo "claude が見つかりません。Claude Code を導入し PATH を確認してください。" >&2; exit 1; }
cleanup(){ find "$AGG" -maxdepth 1 -name '*.jsonl' -delete 2>/dev/null || true; }   # 集約を掃除(同期汚染を最小化。元データは安全)
trap cleanup EXIT
cd "$HUB" && command claude --resume "$@"
