# Architecture

## Data layout
```
<sync folder>/_ClaudeCode/
  sessions/projects/   # transcripts (the real data)
  skills/              # optional shared skills
  locks/               # <encoded-project>.lock | ACTIVE.lock
  exports/
```
Each machine links its own `~/.claude/projects` (and optionally `~/.claude/skills`) to the
folders above:
- **Windows:** directory **junction** (`mklink /J`) — no admin / no Developer Mode needed, works across local volumes.
- **macOS / Linux:** **symlink** (`ln -s`).

Per-machine configuration is stored in `~/.claude/session-sync.local.conf` (NOT synced):
```
share=<abs path to _ClaudeCode>
linkProjects=true
linkSkills=true|false
lockScope=project|global
```

## Path encoding
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, where `<encoded-cwd>` =
the absolute cwd with `[^A-Za-z0-9]` → `-`. This is OS-dependent, so the same logical
project has different folder names per OS. `resume-other` copies a `.jsonl` into the
folder name that matches the **target** machine's working directory, enabling resume.

## Locking
- **project scope (default):** lock file named after the encoded cwd. Different projects
  run concurrently across machines; the same project is mutually excluded.
- **global scope:** a single `ACTIVE.lock`.
- `cc` holds the lock for the lifetime of the `claude` process (keyed by PID).
- Hooks key the lock by Claude's `session_id`; SessionStart acquires (warns, never overwrites,
  on conflict), SessionEnd releases only its own lock.

## Why not sync all of ~/.claude?
`~/.claude.json`, `settings.json`, `.credentials.json`, and `plugins` contain
machine/account-specific state and secrets (oauth account, user id, auth tokens). Only
`projects` (and optionally `skills`) are portable, so only those are linked.
