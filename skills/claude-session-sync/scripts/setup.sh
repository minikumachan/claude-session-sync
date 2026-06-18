#!/usr/bin/env bash
#  claude-session-sync : setup / link / status  (macOS / Linux)
#  components: projects, skills (symlink) / mcp (file sync).  transport: folder | git
#  Destructive `link` is a dry-run unless --yes.
set -euo pipefail
CLAUDE="$HOME/.claude"
CFG="$CLAUDE/session-sync.local.conf"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get(){ [[ -f "$CFG" ]] && grep -E "^$1=" "$CFG" | head -n1 | cut -d= -f2- | tr -d '\r' || true; }
asbool(){ local v="$1" def="$2"; [[ -z "$v" ]] && { echo "$def"; return; }; [[ "$v" == "true" ]] && echo true || echo false; }
onoff(){ [[ "$1" == "true" ]] && echo ON || echo OFF; }

SHARE=""; LOCKSCOPE=""; PHASE="all"; STATUS=0; YES=0
P_SET=""; S_SET=""; M_SET=""; TRANSPORT=""; GITREMOTE=""; CREATEREMOTE=0
while [[ $# -gt 0 ]]; do case "$1" in
  --share) SHARE="$2"; shift 2;;
  --projects) P_SET=true; shift;;     --no-projects) P_SET=false; shift;;
  --skills) S_SET=true; shift;;       --no-skills) S_SET=false; shift;;
  --mcp) M_SET=true; shift;;          --no-mcp) M_SET=false; shift;;
  --lock-scope) LOCKSCOPE="$2"; shift 2;;
  --transport) TRANSPORT="$2"; shift 2;;
  --git-remote) GITREMOTE="$2"; shift 2;;
  --create-remote) CREATEREMOTE=1; shift;;
  --phase) PHASE="$2"; shift 2;;
  --status) STATUS=1; shift;;
  --yes) YES=1; shift;;
  *) echo "不明な引数: $1" >&2; shift;;
esac; done

COMP_P="${P_SET:-$(asbool "$(get shareProjects)" "$(asbool "$(get linkProjects)" true)")}"
COMP_S="${S_SET:-$(asbool "$(get shareSkills)"   "$(asbool "$(get linkSkills)" false)")}"
COMP_M="${M_SET:-$(asbool "$(get shareMcp)" false)}"
[[ -z "$LOCKSCOPE" ]] && LOCKSCOPE="$(get lockScope)"; [[ -z "$LOCKSCOPE" ]] && LOCKSCOPE=project
[[ -z "$TRANSPORT" ]] && TRANSPORT="$(get transport)"; [[ -z "$TRANSPORT" ]] && TRANSPORT=folder

if [[ $STATUS -eq 1 || "$PHASE" == "status" ]]; then
  echo "=== session-sync 状態 ($(uname -s)) ==="
  echo "config: $CFG (存在=$([[ -f $CFG ]] && echo yes || echo no))"
  echo "transport=$TRANSPORT  components: projects=$(onoff "$COMP_P") skills=$(onoff "$COMP_S") mcp=$(onoff "$COMP_M")  (lockScope=$LOCKSCOPE)"
  echo "share: $(get share)"
  if [[ "$TRANSPORT" == "git" ]]; then
    echo "store: $(get store)"; echo "remote: $(get gitRemote)"
    st="$(get store)"; [[ -n "$st" && -d "$st/.git" ]] && { echo "  リモートロック:"; git -C "$st" ls-remote --heads origin 'refs/heads/locks/*' 2>/dev/null | sed 's/^/    /' || echo "    (取得不可)"; }
  fi
  for n in projects skills; do
    p="$CLAUDE/$n"
    if [[ -L "$p" ]]; then echo "  ~/.claude/$n -> $(readlink "$p")"; elif [[ -e "$p" ]]; then echo "  ~/.claude/$n: 実フォルダ(未リンク)"; fi
  done
  s="$(get share)"; [[ -n "$s" ]] && echo "  MCP共有ファイル: $s/mcp/servers.json  存在=$([[ -f "$s/mcp/servers.json" ]] && echo yes || echo no)"
  exit 0
fi

# === git transport: ローカルストア repo を準備し SHARE を決める ===
if [[ "$TRANSPORT" == "git" ]]; then
  command -v git >/dev/null 2>&1 || { echo "git が見つかりません(git transport に必要)。git を導入するか --transport folder を使ってください。" >&2; exit 1; }
  STORE="$(get store)"; [[ -z "$STORE" ]] && STORE="$CLAUDE/session-sync-store"
  REMOTE="$GITREMOTE"; [[ -z "$REMOTE" ]] && REMOTE="$(get gitRemote)"
  if [[ $CREATEREMOTE -eq 1 && -z "$REMOTE" ]]; then
    command -v gh >/dev/null || { echo "--create-remote には gh が必要(または --git-remote を指定)" >&2; exit 1; }
    login="$(gh api user --jq .login)"
    gh repo create "$login/claude-session-store" --private >/dev/null 2>&1 || true
    REMOTE="https://github.com/$login/claude-session-store.git"
    echo "✔ 非公開リモートを作成: $REMOTE"
  fi
  if [[ ! -d "$STORE/.git" ]]; then
    cloned=0
    if [[ -n "$REMOTE" ]] && git ls-remote --heads "$REMOTE" >/dev/null 2>&1 && [[ -n "$(git ls-remote --heads "$REMOTE" 2>/dev/null)" ]]; then
      git clone -q "$REMOTE" "$STORE"; cloned=1
    fi
    if [[ $cloned -eq 0 ]]; then
      mkdir -p "$STORE"; git -C "$STORE" init -q; git -C "$STORE" symbolic-ref HEAD refs/heads/main
      [[ -n "$REMOTE" ]] && git -C "$STORE" remote add origin "$REMOTE"
    fi
  else
    [[ -n "$REMOTE" && -z "$(git -C "$STORE" remote 2>/dev/null)" ]] && git -C "$STORE" remote add origin "$REMOTE"
    if [[ -n "$(git -C "$STORE" remote 2>/dev/null)" ]]; then git -C "$STORE" fetch -q origin 2>/dev/null || true; git -C "$STORE" merge -q --no-edit origin/main 2>/dev/null || true; fi
  fi
  git -C "$STORE" config user.email >/dev/null 2>&1 || { git -C "$STORE" config user.email 'claude-session-sync@localhost'; git -C "$STORE" config user.name 'claude-session-sync'; }
  SHARE="$STORE/_ClaudeCode"
  echo "✔ git ストア: $STORE  (remote: ${REMOTE:-未設定=ローカルのみ})"
fi

[[ -z "$SHARE" ]] && SHARE="$(get share)"
[[ -z "$SHARE" ]] && { echo "共有フォルダ指定が必要:  setup.sh --share '<.../_ClaudeCode>'  (git なら --transport git --git-remote <url>)" >&2; exit 1; }
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
  echo "transport=$TRANSPORT"
  [[ "$TRANSPORT" == "git" ]] && echo "store=$STORE"
  [[ "$TRANSPORT" == "git" && -n "${REMOTE:-}" ]] && echo "gitRemote=$REMOTE"
} > "$CFG"
echo "✔ config 保存: transport=$TRANSPORT projects=$(onoff "$COMP_P") skills=$(onoff "$COMP_S") mcp=$(onoff "$COMP_M")"

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

if [[ "$TRANSPORT" == "git" ]]; then
  git -C "$STORE" config core.autocrlf false 2>/dev/null || true   # .jsonl の EOL 破損防止
  [[ -e "$STORE/.gitattributes" ]] || printf '* -text\n' > "$STORE/.gitattributes"
  for d in "$SHARE/sessions/projects" "$SHARE/locks" "$SHARE/exports" "$SHARE/skills" "$SHARE/mcp"; do
    [[ -d "$d" ]] && [[ ! -e "$d/.gitkeep" ]] && : > "$d/.gitkeep"
  done
  git -C "$STORE" add -A
  [[ -n "$(git -C "$STORE" status --porcelain)" ]] && git -C "$STORE" commit -q -m "init store $(date -u +%FT%TZ) $(hostname)"
  if [[ -n "$(git -C "$STORE" remote 2>/dev/null)" ]]; then
    git -C "$STORE" branch -M main 2>/dev/null || true
    git -C "$STORE" push -u origin main 2>&1 || echo "(push 失敗: 後で sync.sh push)"
    echo "✔ git ストアを remote へ push(以後 cc.sh が pull/push を自動化)"
  else
    echo "ℹ remote 未設定。後で --transport git --git-remote <url> で接続可。"
  fi
fi

if [[ "$COMP_M" == "true" ]]; then
  echo; echo "ℹ MCP 共有は ON。bash mcp-sync.sh --export / --import --yes(~/.claude.json はリンクしない)。"
fi
chmod +x "$DIR"/*.sh 2>/dev/null || true
echo "完了。起動は cc.sh / 取り込みは resume-other.sh。"
