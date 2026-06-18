# Changelog

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
