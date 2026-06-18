# Changelog

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
