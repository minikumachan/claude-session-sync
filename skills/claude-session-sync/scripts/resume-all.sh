#!/usr/bin/env bash
#  claude-session-sync : 全パス・全デバイスの履歴を native `claude --resume` で選べるようにする (macOS / Linux)
#  全 .jsonl を「同期しないローカル集約フォルダ」へハードリンクで集め、そこを cwd にして claude --resume を起動。
#    resume-all.sh [--limit N] [--days N] [--all] [--dry-run]
set -uo pipefail
LIMIT=100; DAYS=0; ALL=0; DRY=0; ARGS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --dry-run) DRY=1; shift;;
  --limit) LIMIT="$2"; shift 2;;
  --days) DAYS="$2"; shift 2;;
  --all) ALL=1; shift;;
  *) ARGS+=("$1"); shift;;
esac; done
CLAUDE="$HOME/.claude"; PROJECTS="$CLAUDE/projects"; CFG="$CLAUDE/session-sync.local.conf"
get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG"|head -n1|cut -d= -f2-|tr -d '\r' || true; }
encode(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
mtime(){ case "$(uname -s)" in Darwin) stat -f %m "$1" 2>/dev/null;; *) stat -c %Y "$1" 2>/dev/null;; esac; }
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
# 候補収集(除外フィルタ)
cand=()
while IFS= read -r -d '' f; do
  case "$f" in "$AGG"/*) continue;; esac
  d="$(basename "$(dirname "$f")")"; b="$(basename "$f" .jsonl)"
  case "$d" in subagents|wf_*) continue;; esac
  case "$b" in agent-*|journal) continue;; esac
  cand+=("$f")
done < <(find "$PROJECTS" -name '*.jsonl' -print0 2>/dev/null)
total=${#cand[@]}
# 新しい順に並べ、読込量を選択(既定: 最近 LIMIT 件)
sorted="$(for f in "${cand[@]+"${cand[@]}"}"; do printf '%s\t%s\n' "$(mtime "$f")" "$f"; done | sort -rn)"
sel=(); now=$(date +%s)
if [[ $ALL -eq 1 ]]; then
  while IFS=$'\t' read -r mt p; do [[ -n "$p" ]] && sel+=("$p"); done <<< "$sorted"
elif [[ $DAYS -gt 0 ]]; then
  cut=$((now - DAYS*86400))
  while IFS=$'\t' read -r mt p; do [[ -n "$p" && "$mt" -ge "$cut" ]] && sel+=("$p"); done <<< "$sorted"
else
  while IFS=$'\t' read -r mt p; do [[ -z "$p" ]] && continue; sel+=("$p"); [[ ${#sel[@]} -ge $LIMIT ]] && break; done <<< "$sorted"
fi
n=0
for f in "${sel[@]+"${sel[@]}"}"; do
  dest="$AGG/$(basename "$f")"
  [[ -e "$dest" ]] || ln "$f" "$dest" 2>/dev/null || cp "$f" "$dest"
  n=$((n+1))
done
if [[ $ALL -eq 1 ]]; then scopeMsg="全件"; elif [[ $DAYS -gt 0 ]]; then scopeMsg="直近${DAYS}日"; else scopeMsg="最近${LIMIT}件"; fi
echo "対象: $n / 全 $total 件 ($scopeMsg)。少ないほど picker が高速。"
[[ $DRY -eq 1 ]] && { echo "[DryRun] $AGG"; exit 0; }
command -v claude >/dev/null 2>&1 || { find "$AGG" -maxdepth 1 -name '*.jsonl' -delete 2>/dev/null; echo "claude が見つかりません。Claude Code を導入し PATH を確認してください。" >&2; exit 1; }
cleanup(){ find "$AGG" -maxdepth 1 -name '*.jsonl' -delete 2>/dev/null || true; }
trap cleanup EXIT
cd "$HUB" && command claude --resume "${ARGS[@]+"${ARGS[@]}"}"
