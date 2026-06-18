# Changelog

**English** | [日本語 (CHANGELOG.ja.md)](CHANGELOG.ja.md) · This project follows [Semantic Versioning](https://semver.org/).

> **In plain words — what this tool does today:** shares your Claude Code history across your
> computers (or syncs it itself via GitHub if you have no sync app), stops two machines from
> editing the same project at once, and adds **`claude -h`** to browse all your history while
> leaving the official **`claude -r`** untouched. Each version's first line below is a plain summary;
> the bullets are the details.

## 1.7.1
**Plain summary:** the `claude -h` screen was reworked to look and feel like the official `claude -r` picker.
- `❯` caret + highlighted current row; columns are **title · relative time ("2 hours ago") · message count · source device** (color-labeled).
- Header with a tab bar and a divider; a bottom key-hints line — matching the official layout.
- **Space** previews a session's contents; **Enter** resumes; `/` search; `q`/Esc quit. (macOS/Linux also support mouse.)

## 1.7.0
**Plain summary:** `claude -r` is back to the official behavior, and a new **`claude -h`** lets you browse all your history (all machines) in a tabbed, paged screen.


- **`claude -r` restored to the official native picker.** The earlier design that hijacked `-r` (which caused `claude -r` to show no history) is removed. The shell wrapper now intercepts **only `-h`**; `-r` and everything else pass straight to the real `claude`, so the official path-scoped picker works exactly as before.
- **New `claude -h` history browser UI** — a tabbed, paged, lazy-loading interactive browser modeled on the official picker:
  - Tabs: *this project (path-scoped, like `-r`) / all history (all devices) / last 7 days* (← → to switch).
  - Only the visible page is scanned (lazy), so it stays fast and stable across hundreds of sessions; PageUp/PageDown to page.
  - Keyboard everywhere (↑↓ select, Enter resume, `/` search, q quit); **mouse wheel/click on macOS/Linux** via python `curses`. Windows is keyboard (like the official `-r`).
  - Rows show the source device (color + label) and a content title (Claude `ai-title`); Enter imports the session into the current folder and runs `claude --resume`.
- **Removed** the standalone `history`, `resume-other`, `resume-all` commands (folded into `claude -h`).
- Migration: re-run `install-shell-wrap` — it removes the old `-r` block and installs the `-h` one automatically.

## 1.6.0
- **Paginated history viewer with device colors and content titles.** `history list` is page-based (`-Page` / `-PageSize`, default 20) and only scans the current page — fast even with hundreds of sessions. Each row shows the **source device** color-coded (`Win/<user>`, `Mac/<user>`, `Linux/<user>`; same-model machines distinguished via an optional `deviceName` the hook records in `devices.map`) and a **content-derived title** (generated fixed-language title > Claude's `ai-title` > first user message).
- **Fixed-language title generation**: `history title` summarizes each conversation into a concise title in the configured `lang` via `claude -p`, cached in `titles.map`.
- **Read-amount control for the all-history picker**: `resume-all` / `claude -r` take `-Limit` (default 100 most-recent), `-Days`, `-All` so the native picker loads quickly.
- New config keys: `lang` (default = OS language) and `deviceName` (default = hostname); set via `setup -Lang` / `-DeviceName`.
- Fix: resolved a `$all` vs `$All` (switch) variable name collision in the history list.

## 1.5.1
Robustness / hardening pass (cross-environment audit) so the tool works for any user on any setup:
- **Encoding**: all `.ps1` are UTF-8 **with BOM** and read config/`.jsonl` with `-Encoding utf8`, fixing garbled text and parse errors on Windows PowerShell 5.1 with Japanese content or non-ASCII paths. `.gitattributes` adds `working-tree-encoding=UTF-8-BOM` so every clone gets a correct BOM.
- **Atomic locking** (folder transport): the lock file is created with `CreateNew` / `noclobber`, removing the check-then-write race.
- **git store integrity**: the store repo is set to `core.autocrlf=false` with a `* -text` `.gitattributes`, so `.jsonl` transcripts are never EOL-rewritten/corrupted.
- **`resume-all` cleanup**: the all-history aggregate is deleted on exit (protects iCloud/Dropbox/OneDrive users where no `.stignore` exists from sync pollution).
- **Preconditions & safety**: `claude`/`git` presence checked with clear errors before any state change; hooks read stdin as UTF-8 (WinPS 5.1 cwd no longer garbled); config written UTF-8/LF and read tolerant of CRLF; `nullglob` in `detect-sync.sh`; exported MCP secret file `chmod 600`; `history` handles non-ASCII and short ids; `claude -r` wrapper calls the real binary to avoid recursion.

## 1.5.0
- **`claude -r` extended to ALL history** (all paths, all devices). Because Claude's `--resume` is scoped to the current project folder and the binary can't be modified, `resume-all` aggregates every session's `.jsonl` (hard links) into a **local, non-synced** folder and opens the native `--resume` picker there — so the picker lists everything.
- `install-shell-wrap.ps1` / `.sh` adds a `claude` shell function (PowerShell profile / bashrc / zshrc) so plain `claude -r` / `--resume` opens the all-history picker; all other args pass straight through to the real `claude`. Uninstall with `-Uninstall` / `--uninstall`.
- The aggregate folder is auto-excluded from sync (`.stignore` via the `.stfolder` root for folder transport, `.gitignore` for git transport), so it never pollutes other devices.
- **No device limit**: folder (Syncthing/iCloud/…) and git transports both support unlimited peers/clones.

## 1.4.0
- **`history` command** — browse, view and resume **all** conversation history from **any** working directory (Claude's built-in `--resume` only shows the current project). Reads `~/.claude/projects` directly, so it surfaces every project from every synced device.
  - `history.ps1 list [-Grep <text>] [-Limit N]` — all sessions, newest first, with project + first-message preview.
  - `history.ps1 view <#|id>` — print a session transcript readably.
  - `history.ps1 resume <#|id>` — import into the current dir and show the `claude --resume` command.
  - `history.ps1 path <#|id>` — print the transcript file path. (`history.sh` mirrors this on macOS/Linux.)

## 1.3.0
- **git transport** — a self-contained sync mode that needs **no external sync app**. A local *store* git repo is pushed/pulled to a git remote (e.g. a private GitHub repo); `cc` pulls on start and pushes on exit. Choose via `setup --transport git --git-remote <url>` (or `--create-remote` to make a private GitHub repo via `gh`). The existing `folder` transport (Syncthing/iCloud/Dropbox/OneDrive/GDrive) remains the default.
- **Distributed locking for git transport** — mutual exclusion via a remote git ref (a unique orphan commit pushed without force); a second machine acquiring the same project's lock is rejected. Verified end-to-end across two simulated machines.
- New `sync.ps1` / `sync.sh` (`pull` / `push` / `status` / `lock` / `unlock`).
- `~/.claude.json`, credentials and settings are never placed in the git store (only projects/skills/mcp).

## 1.2.0
- **Interactive installer**: `install.ps1` / `install.sh` with no flags now runs a guided wizard — asks *share or keep local* → *which components* → *which sync folder* → *install hooks?*, branching at each step.
- Added `-Local` / `--local` to install the skill without setting up sharing.
- `SKILL.md` documents a **conversational decision-flow** so Claude asks the user at each branch point (share-or-not, components, destination, lock mode, `-Yes` confirmation).
- **Full bilingual documentation** (English `README.md` + 日本語 `README.ja.md`) with badges and language switcher.

## 1.1.0
- **Three independently toggleable components**: `projects`, `skills`, `mcp` (each ON/OFF via `setup` flags / config).
- **MCP sharing** (`mcp-sync`): export/import `mcpServers` between `~/.claude.json` and a shared file — `~/.claude.json` is never linked. Backs up and validates before writing; warns when `env` secrets would be shared; `--strip-env` to exclude them.
- **Safety-first migration**: destructive `link` and MCP `import` are **dry-run unless `-Yes`/`--yes`** is passed, with explicit warnings and automatic backups.
- Config keys renamed to `shareProjects` / `shareSkills` / `shareMcp` (legacy `linkProjects`/`linkSkills` still read).
- Installers updated with `-Skills` / `-Mcp` / `-NoProjects` selectors.

## 1.0.0
- Initial release.
- Cross-platform (Windows / macOS / Linux) sharing of `~/.claude/projects` (and optional `~/.claude/skills`) over any file-sync folder.
- Config-driven (`~/.claude/session-sync.local.conf`) — no hardcoded paths.
- `setup` (prepare/link/status), `cc` (lock-guarded launcher), `resume-other` (import another device's session).
- Per-project (or global) locking.
- Optional auto-lock hooks via `install-hooks` (SessionStart/SessionEnd).
- Sync-provider auto-detection (`detect-sync`) and one-shot installers (`install.ps1` / `install.sh`).
