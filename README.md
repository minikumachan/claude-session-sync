# claude-session-sync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-skill%20%2B%20plugin-8A2BE2)

**English** | [日本語 (README.ja.md)](README.ja.md) · [Changelog](CHANGELOG.md)

## What is this?
A tool that **shares your Claude Code conversation history across your computers** (Windows, macOS, Linux).
For example: start a chat on your Windows PC at home, then open it on your MacBook while you're out.
It also **prevents the history corruption that happens when two machines edit the same project at once.**

It stores the shared history in a **cloud-sync folder you already use** (Syncthing, iCloud, Dropbox, OneDrive, Google Drive).
No sync app? You can also let **this tool do the syncing itself, over GitHub.**

## What you get
- 🔁 **Share history between machines** (Windows ⇄ Mac, etc. — no device limit).
- 🧩 Choose **which of 3 things to share**: conversation history / skills / MCP settings (turn on only what you want).
- 🔒 **Automatically blocks editing the same project on two machines** at once (different projects in parallel are fine).
- 🗂 **`claude -h` shows all your history** in a tabbed, paged browser — each row is color-labeled by which computer it came from.
- 🏷 **Automatic conversation titles**: sessions are renamed to a clear, short title that matches the conversation's content and language (see below).
- 🔐 **Your credentials and settings are never shared** (logins stay on each machine).
- 🛟 **Safety first**: anything destructive first does a *dry run* showing what it will do, and only acts when you add `-Yes` — always after making a backup.

## Quick glossary
- **Sync folder**: a folder kept in sync across machines by Syncthing / iCloud / etc.
- **Link**: a "stand-in" for a folder (a powerful shortcut). Used to point Claude's history folder at the sync folder.
- **Component**: a thing you can share — `projects` (history) / `skills` / `mcp`.
- **Sync method (2)**: `folder` = rely on your sync app · `git` = this tool syncs via GitHub (no sync app needed).

## Install
```bash
git clone https://github.com/minikumachan/claude-session-sync
cd claude-session-sync
# Run with no flags for a guided setup (share or not? → what to share? → which folder?):
pwsh -File install.ps1     # Windows
bash install.sh           # macOS / Linux
```
The installer does the safe preparation automatically; **you run the actual link step yourself last** (preview first, then confirm):
```powershell
# Windows: after fully closing Claude
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link        # dry run (preview)
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link -Yes   # apply
```
> Or install as a plugin: `/plugin marketplace add minikumachan/claude-session-sync` → `/plugin install claude-session-sync`

## Usage
| What you want | Command |
|---|---|
| Resume in the current project (official) | **`claude -r`** — the native Claude picker, unchanged. Shows this project's history. |
| **See all history from all machines** | **`claude -h`** — the tabbed history browser (below). Enabled by `install-shell-wrap`. |
| Launch with same-project locking | `cc.ps1` / `cc.sh` (use instead of `claude`; passes your args through) |
| Check status | `setup.ps1 -Status` / `setup.sh --status` |
| Change what's shared | re-run `setup` with `-Skills` / `-Mcp` / `-NoProjects`, etc. |
| Name this machine | `setup.ps1 -DeviceName "Home-Win"` |

### `claude -h` (history browser)
The official `claude -r` only lists the current folder's history. `claude -h` lists **all projects from all machines**, in a familiar picker-style screen.
- **Search box at the top**: just start typing to filter live (Backspace edits, Esc clears or quits).
- **Tabs** (← →): `This project` / `All history` / `Last 7 days` / `★ Favorites`
- **Two-line entries**: title on top (favorites get a ★), then *device · message count · time · project*, separated by a divider.
- **Paging** (PageUp / PageDown): only what's on screen is loaded, so it's fast and stable even with many sessions.
- **Keys**: ↑↓ select · Enter resume · type to search · Esc quit. **Mouse** (wheel/click) works on macOS/Linux.
- **Tab opens an actions menu** for the selected conversation:
  - ⭐ **Favorite / unfavorite** — manage them in the `★ Favorites` tab. Saved to the shared folder, so it's **the same on every machine**.
  - 🍴 **Fork (branch)** — duplicate the conversation and continue it as a separate branch; the original is left untouched.
  - 🧵 **Start new with context** — begin a **new** conversation that inherits the gist (original request + recent exchanges) of the selected one.
- Each row is **color-labeled by source computer** (`Win/<user>`, `Mac/<user>`, …).

### Automatic conversation titles
As a conversation grows, Claude **reads the content and renames the session to a clear, short title** (e.g. "Fix search box alignment").
- **The title matches the conversation's language** (a Japanese chat gets a Japanese title). You can pin a fixed language with `titleLang`.
- Titles show **first** in `claude -h` (above Claude's built-in auto-title). They're saved to the shared folder, so **every machine sees the same title**.
- Enable it by running `install-hooks.ps1` / `install-hooks.sh` (updates after each response). Turn it off with `setup.ps1 -NoAutoTitle` (/ `--no-auto-title`).
- How it works: every few turns, only a short excerpt of the conversation is sent to a small model (default `haiku`) to produce the title. **No credentials are sent.** The temporary session used for generation is deleted automatically and never appears in the list.

## Two sync methods (your choice)
| Method | Sync app | Notes |
|---|---|---|
| **folder** (default) | required (Syncthing / iCloud / Dropbox / OneDrive / Google Drive) | Rides on your existing cloud sync. Always live. |
| **git** | **none** | This tool syncs via a **private GitHub repo**. For people who don't want a sync app. |

For git: `setup.ps1 -Transport git -GitRemote <repo-url>` (add `-CreateRemote` to auto-create a private repo).
Either way, **your credentials and settings are never shared.**

## Safety & rollback
- A timestamped backup (`*_backup_<time>` / `*_local_old`) is made before any link.
- To undo (removes only the link; your data stays in the sync folder):
  - Windows: `Remove-Item ~/.claude/projects` → `Rename-Item ~/.claude/projects_local_old projects`
  - macOS/Linux: `rm ~/.claude/projects` → `mv ~/.claude/projects_local_old ~/.claude/projects`
- Turn on **File Versioning** in your sync app for extra peace of mind.

## Troubleshooting
- **`claude -r` shows no history**: a stale setting may remain. Re-run `install-shell-wrap` to restore the official `claude -r`, then open a **new terminal**.
- **`claude -h` doesn't work**: run `install-shell-wrap.ps1` (/ `.sh`), then open a new terminal.
- **Windows blocks a script**: run `powershell -ExecutionPolicy Bypass -File <script>`, or once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- **Don't open the same project on two machines at once**: locking protects you, but pick one launch method — `cc`, or the auto-lock hooks.

## Requirements
- Windows / macOS / Linux with Claude Code.
- `git` only for the git method. `python3` for some macOS/Linux features (e.g. `claude -h`). Windows PowerShell 5.1 or 7 both work.

## License
MIT — see [LICENSE](LICENSE).
