# claude-session-sync

Share **Claude Code conversation history** (and optionally your **skills**) across
your machines using a file-sync folder you already have — **Syncthing, iCloud Drive,
Dropbox, OneDrive, Google Drive** — and never corrupt a transcript by editing the same
project from two devices at once.

- ✅ **Windows / macOS / Linux** (Win⇄Mac, Mac⇄Mac, Win⇄Win, …)
- ✅ Shares only `~/.claude/projects` (and optionally `~/.claude/skills`) — **never** your credentials or settings
- ✅ **Per-project locking** prevents simultaneous-access conflicts (different projects can run in parallel)
- ✅ Bring another device's conversation in and **resume it locally**
- ✅ Optional **auto-lock hooks** — normal `claude` startup is protected, no wrapper needed

> ⚠️ It does **not** move or sync `~/.claude.json`, `settings.json`, `.credentials.json`,
> or `plugins`. Authentication stays local to each machine.

---

## How it works

Claude Code stores transcripts at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`,
where `<encoded-cwd>` is the absolute working directory with every non-alphanumeric
character replaced by `-`. This tool points `~/.claude/projects` at a folder inside your
sync directory (via a **junction** on Windows or a **symlink** on macOS/Linux):

```
<your sync folder>/_ClaudeCode/
  sessions/projects/   ← real transcripts live here (each machine links ~/.claude/projects to this)
  skills/              ← optional shared skills
  locks/               ← <encoded-project>.lock  (or ACTIVE.lock in global mode)
  exports/
```

Your existing sync tool (Syncthing/iCloud/…) keeps everything up to date in near real time.

> **Cross-OS note:** because the encoded folder name depends on the OS path, the same
> project gets a different folder name on Windows vs macOS, so `claude --resume` won't
> automatically list another OS's sessions. Use `resume-other` to import one and resume it.

---

## Install

### Option A — one-shot installer (recommended)
```bash
git clone https://github.com/Minikuma/claude-session-sync
cd claude-session-sync
# Windows (PowerShell):
pwsh -File install.ps1 -WithSkills -Hooks
# macOS / Linux:
bash install.sh --with-skills --hooks
```
The installer copies the skill into `~/.claude/skills/`, auto-detects your sync folders,
runs the **non-destructive** prepare step, and (with `--hooks`) installs the auto-lock hooks.
Then **close Claude Code completely** and create the links:
```bash
# Windows
pwsh -File "$env:USERPROFILE\.claude\skills\claude-session-sync\scripts\setup.ps1" -Phase link
# macOS / Linux
bash "$HOME/.claude/skills/claude-session-sync/scripts/setup.sh" --phase link
```

### Option B — as a Claude Code plugin
```
/plugin marketplace add Minikuma/claude-session-sync
/plugin install claude-session-sync
```
Then ask Claude: *“set up cross-device session sync”* and it will run the skill.

---

## Usage

| Goal | Command |
|---|---|
| Start Claude with a lock (no hooks) | `cc.ps1` / `cc.sh` (pass any `claude` args) |
| List sessions from all devices | `resume-other.ps1 -List` / `resume-other.sh -l` |
| Import another device's session | `resume-other.ps1 -SessionId <id> -TargetDir <dir>` then `claude --resume <id>` |
| Show status | `setup.ps1 -Status` / `setup.sh --status` |
| Clear a stale lock | `cc.ps1 -Unlock` / `cc.sh --unlock` |
| Remove auto-lock hooks | `install-hooks.ps1 -Uninstall` / `install-hooks.sh --uninstall` |

Scripts live in `~/.claude/skills/claude-session-sync/scripts/`.

### Locking
Default scope is **`project`**: a lock is keyed to the working directory, so two machines
can work on *different* projects simultaneously, but the *same* project is blocked. Use
`-LockScope global` for a single machine-wide lock.

With **hooks installed**, locks are acquired/released automatically around every session
(keyed by Claude's `session_id`); on conflict the session starts but a loud warning is
injected. Without hooks, launch via `cc` to enforce the lock.

---

## Remote control from a phone
Continuing the *same* conversation across OSes automatically isn't possible (path encoding).
To drive a session from your phone while away, use Claude Code's built-in **Remote Control**
(`claude remote-control`, requires v2.1.51+ and a claude.ai login). Keep the host machine
awake; connect from the Claude mobile app / claude.ai/code.

---

## Safety
- A timestamped backup is made before any link (`*_backup_<timestamp>`); the original folder
  is moved to `*_local_old`, not deleted.
- Merges never overwrite existing files (union only).
- Enable **File Versioning** in your sync tool for an automatic version history of transcripts.

## Uninstall / rollback
```bash
# Windows
Remove-Item ~/.claude/projects; Rename-Item ~/.claude/projects_local_old projects
# macOS / Linux
rm ~/.claude/projects; mv ~/.claude/projects_local_old ~/.claude/projects
```
(only the link is removed — your data stays in the sync folder). Same for `skills`.

## License
MIT — see [LICENSE](LICENSE).
