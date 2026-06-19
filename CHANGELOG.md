# Changelog

**English** | [日本語 (CHANGELOG.ja.md)](CHANGELOG.ja.md) · This project follows [Semantic Versioning](https://semver.org/).

> **In plain words — what this tool does today:** shares your Claude Code history across your
> computers (or syncs it itself via GitHub if you have no sync app), stops two machines from
> editing the same project at once, and adds **`claude -h`** to browse all your history while
> leaving the official **`claude -r`** untouched. Each version's first line below is a plain summary;
> the bullets are the details.

## 1.17.0
**Plain summary:** `claude -h` now **shows which conversations are currently in use** and **stops you from opening one that's in use, telling you to disconnect first** (prevents simultaneous-access corruption).
- **In-use indicator.** Reads the shared `locks/` (valid `session=<sid>` locks, < 12h) on each redraw and shows "● in use: <device>" (red) on that conversation's meta line.
- **In-use protection.** Trying to open an in-use conversation (Enter / fork / resume-with-permission) shows the device using it and asks you to **disconnect on that device first**, then aborts. Press **F** to force-open anyway (dangerous). Works on Windows (arrow keys) and macOS/Linux (curses, incl. mouse).

## 1.16.1
**Plain summary:** the `claude -a` "view/operate" items used to just **print commands (code)** — now they're **text-GUI screens you operate, executing in place** (destructive actions gated by a dry-run and/or a warning + confirmation).
- **Sync status**: a formatted text panel (transport / location / per-component share state / toggles) instead of raw `setup` output.
- **Start sharing / re-link**: toggle projects/skills/mcp on screen → [dry-run] → warning + y/N → [apply] (runs `setup` internally; no command strings shown).
- **MCP share**: status / export / (export-incl-secrets, confirmed) / import (destructive, confirmed) from the menu.
- **Restore original**: pick a component, warn + confirm, then unlink and restore locally (rename the `_local_old` backup, or copy from the share if none). Shared data is kept.
- Windows (arrow keys) and macOS/Linux (numbered menu).

## 1.16.0
**Plain summary:** on a device switch, the notice now also **verifies the working path exists and that sync/migration actually completed** (warns about conflicts / in-transit files / not-yet-arrived history so you don't redo work on a half-synced state). And **resuming from history now inherits that conversation's previous model, thinking depth and permission.**
- **Sync/migration health check.** When a device switch is detected, a fast check confirms the share is reachable, **this conversation's history (.jsonl) has arrived on this device**, and there are no **sync conflicts (`*.sync-conflict*`) / in-transit files (`~syncthing~*` …)** in the history or work folder; problems are surfaced as concise warnings (avoiding wasted token spend). The suggested work path is **existence-verified** before it's offered.
- **Inherit settings on resume.** A SessionStart hook records sid→(model/effort/permission) in `<share>/sessions/launchopts.map` (env `CSS_LAUNCH_*` preferred, else stdin model + existing values). `claude -h` resume/fork and `boot-launch` last/resume restore those (plus the transcript's last model as a fallback) and pass `--model/--effort/--permission-mode`. An explicit per-item permission still wins.
- Fix: corrected an array-join bug (stray comma) in the launch-options recorder; map writes are locked and UTF-8.

## 1.15.0
**Plain summary:** added **permission switching** alongside model and thinking depth, available from `claude -a`, `claude -h`, and a new `/cc-mode` command. Permission ranges from `plan` up to a **full bypass** (`--dangerously-skip-permissions` — even env-value reading/copying and arbitrary commands run unprompted); escalating to high levels asks for re-confirmation.
- **Full permission support.** `default`/`plan`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`(⚠)/`full`(⚠⚠ = full bypass). `full` maps to `--dangerously-skip-permissions`; the rest to `--permission-mode <value>`.
- **`claude -a`**: each auto-start item now sets model/thinking/**permission**/remote (new "permission" row in the item editor). Switching to **bypassPermissions/full prompts a y/N warning**. `install-autostart` gains `-Permission`/`--permission`; boot.json gains a `permission` field.
- **`claude -h`**: the actions menu (Tab) gains **[r] resume with a changed permission** — pick a level and resume with `--permission-mode` / `--dangerously-skip-permissions` (high levels warn).
- **`/cc-mode`** (new synced skill `skills/cc-mode`): shows the current model/thinking/permission and how to change each mid-session. Persistent in-session switches use the built-ins (`/model`, Shift+Tab); full-bypass etc. is set at launch.
- High-privilege levels are powerful, so they require an explicit warning + confirmation. Use only where you trust the workload.

## 1.14.0
**Plain summary:** added **automatic device-switch detection** — resume a conversation on a different machine (including switching back) and Claude is told you switched devices, plus the **correct working path for this machine**.
- **SessionStart hook `hook-devswitch.*`.** Records each conversation's most-recent device + working folder in `<share>/sessions/lastseen.map`; on resume from a different device it prints a notice (and the matching path) to stdout, which SessionStart adds to Claude's context.
- **Working-path inference.** Uses the previous cwd if it exists locally, otherwise finds the **same home-relative structure** on this device (Win `C:\Users\X\proj` ↔ macOS/Linux `/Users|/home/Y/proj`), so work continues with the right absolute path even when the OS path format differs.
- `install-hooks` now also registers `hook-devswitch` on SessionStart. Added a **device-switch notice on/off** toggle to `claude -a` and conf key `deviceSwitchNotice` (default on). Only metadata is recorded — no conversation text or secrets are sent.

## 1.13.0
**Plain summary:** removed the phone-trigger watcher entirely (use official Dispatch to start a new session on an idle PC from your phone), turned `claude -a` into a settings hub (sync status, auto-title on/off, start sharing, restore original history location), and fixed `claude -h`'s history list breaking on resize/refocus.
- **Removed remote-watch.** Deleted `remote-watch.{ps1,sh}`, `-Watch`/`remoteWatch`/`remoteWatchDir`, the watch folder, and the resident registration (config traces purged too). Use Anthropic's **Dispatch** (Claude desktop app) for phone-initiated starts.
- **`claude -a` is now a settings hub.** Besides managing auto-start it shows sync status (transport/location/projects·skills·mcp), toggles **auto-titling on/off**, and guides **start sharing / re-link / MCP share / restore original history location**. Destructive actions (link/restore/import) are shown as commands, not executed. Cleaner ASCII layout with grouped sections.
- **Fixed `claude -h` resize/refocus glitch.** The history list repaints when the window width/height changes without waiting for a keypress.

## 1.12.1
**Plain summary:** fixes display glitches in the `claude -a` menu — a crooked box border in Japanese/CJK terminals, and the layout staying broken after a window resize or refocus.
- **ASCII-only rendering.** Dropped box-drawing borders and `❯`/`…` (East-Asian *ambiguous-width* characters that render double-width in CJK terminals and misalign) in favor of ASCII headers and a `>` marker. Editor labels are padded by **display width** so the colons line up.
- **Auto-redraw on resize/refocus.** The menu detects window-width changes without waiting for a keypress and repaints, so it no longer stays broken after you resize the window.

## 1.12.0
**Plain summary:** auto-start at login is now richer — register **multiple** conversations to launch, each with its own **model and thinking depth** (brainstorming defaults to Sonnet + medium thinking). Items that **resume a specific conversation keep that conversation's own model/depth**.
- **Multiple boot items.** Stored in `~/.claude/session-sync.boot.json` (per-device array); all launch at login (the last in the same window, the rest in their own windows). The multi-instance check runs once for the batch.
- **Model / thinking depth.** `new` (brainstorming) items accept `--model` (default `sonnet` = latest) and `--effort` (low/medium/high/xhigh/max, default `medium`). `last`/`resume` items add neither, so the conversation's own settings are used.
- **`claude -a` is now a list manager.** Add/edit/delete items and set type, model, thinking depth, and remote with arrow keys (Enter edit/add, D delete, S save). `install-autostart` gains `-Model`/`-Effort`/`-Apply` (`--model`/`--effort`/`--apply`).
- Note: model is a `claude --model` alias/ID; `sonnet` means the latest Sonnet (you can also type a specific ID).

## 1.11.0
**Plain summary:** auto-start / remote settings now have a one-command interactive menu — **`claude -a`** — driven entirely by arrow keys, so you don't have to remember any flags.
- **`claude -a` interactive setup.** Same feel as `claude -h` (the history browser): use arrow keys to toggle *which conversation to launch / remote / multi-instance check / start-from-phone*, then Enter to save & enable (Tab turns everything off). "Always resume a specific one" lets you pick from a list of recent conversations (new `autostart-ui.{ps1,sh}`).
- **Or set it up by chatting.** Say "set up auto-start" and Claude configures it for you.
- `install-shell-wrap` now also intercepts `-a`/`--autostart` (like `-h`; `-r` etc. stay native). Saving/registration still delegates to v1.10.0's `install-autostart.*` (same behavior).

## 1.10.0
**Plain summary:** you can now auto-start `claude` at login (new / resume a specific conversation, with a multi-instance check and optional remote) and trigger a Remote Control session from your phone.
- **Auto-start at login.** `install-autostart` (Windows `.ps1` / macOS·Linux `.sh`) launches `claude` when you log in: `bootLaunch=new`, `last` (resume the most recent conversation), or `<sid>` (always resume a specific one). Implemented via a Startup-folder shortcut on Windows and a LaunchAgent / `.desktop` autostart on macOS/Linux (**no admin required**).
- **Multi-instance check.** Before launching it inspects the shared `locks/`; if **another device** is active (a valid lock < 12h old) it **aborts with a warning**, preventing Windows+Mac simultaneous use from corrupting history (`.sync-conflict`).
- **Remote on/off at startup.** `bootRemote=true|false|ask`. `true` launches with `claude --remote-control`, so as long as the PC is on you can drive it from the Claude app / claude.ai. `ask` prompts at startup (defaults to off after 8s). Requires Claude Code v2.1.51+ / a claude.ai login.
- **Start from your phone + start a specific conversation.** A resident watcher (`remote-watch`, enabled with `-Watch`/`--watch`) monitors `<share>/remote/inbox`; dropping a file there launches `claude --remote-control` (with `--resume <sid>` if a session-id appears in the name/content). **No extra ports or public exposure** — it rides your existing sync folder. Then drive the session from the Claude app / claude.ai. Works **only while the PC is on**.
- **New scripts**: `boot-launch.{ps1,sh}`, `remote-watch.{ps1,sh}`, `install-autostart.{ps1,sh}`. Settings are stored per-device (not synced) in `session-sync.local.conf` as `bootLaunch`/`bootRemote`/`bootCheckMulti`/`remoteWatch`/`remoteWatchDir`.
- **Fix**: `setup.ps1` crashed when re-run without `-AutoTitle`/`-NoAutoTitle` (it called `.ContainsKey`, which `OrderedDictionary` lacks); changed to `.Contains`.

## 1.9.0
**Plain summary:** `claude -h` gains favorites, plus fork-a-conversation and start-new-with-context — all from a new actions menu (Tab).
- **★ Favorites + a Favorites tab.** Mark any conversation as a favorite and manage them in the new `★ Favorites` tab; favorited rows show a ★. Favorites are stored in `<share>/sessions/favorites.txt` (and a local copy), so they're the same on every machine.
- **Fork a conversation.** Duplicate a session and continue it as a separate branch via Claude's native `--fork-session` (a new session ID is created; the original is untouched).
- **Start a new conversation with context.** Begin a fresh session that inherits the gist of the selected one (its original request + recent exchanges) using `--append-system-prompt` — not a full replay.
- **New actions menu**: press **Tab** on a selected item for *resume / favorite / fork / new-with-context / preview*. (Single-letter keys still go to live search in the list.)

## 1.8.0
**Plain summary:** conversations now get an automatic, content-aware title — sessions are renamed to a clear short title in the conversation's own language as you work.
- **Auto-titling via a `Stop` hook.** Every few user turns (`titleEvery`, default 5), a background job sends a short excerpt of the conversation to a small model (`titleModel`, default `haiku`) and writes a concise title to `<share>/sessions/titles.map` (or `~/.claude/sessions/titles.map` if you don't share). `claude -h` shows this title first (above Claude's built-in `ai-title`), so every machine sees the same name.
- **Language-aware.** `titleLang=auto` (default) writes the title in the conversation's own language; set `ja`/`en`/… to pin one.
- **New scripts**: `title-gen.{ps1,sh}` (generator) and `hook-title.{ps1,sh}` (the throttled Stop hook). `install-hooks` now registers the `Stop` hook alongside the existing lock hooks; `setup` gains `-AutoTitle`/`-NoAutoTitle`/`-TitleLang` (`--auto-title`/`--no-auto-title`/`--title-lang`) and writes `autoTitle`/`titleLang`/`titleModel`/`titleEvery`.
- **Private & tidy.** Only a short conversation excerpt is sent — never credentials. The temporary session used for generation runs in a dedicated working directory, is deleted automatically, and is filtered out of `claude -h`. A guard env var (`CSS_TITLEGEN`) prevents the lock/title hooks from re-entering during generation.

## 1.7.5
**Plain summary:** fixed the search box's right edge being misaligned in `claude -h`.
- The top border was sized by character *count*, so wide characters (the 🔍 icon and Japanese label/text count as 2 display columns) pushed the right corner out of line with the bottom border. Borders and padding are now sized by **display width** (full-width CJK/emoji = 2), so the box stays square — including when you type wide characters into the search field. Fixed on both Windows (`SetCursorPosition` build) and macOS/Linux (curses, via `unicodedata`).

## 1.7.4
**Plain summary:** `claude -h` no longer redraws the whole screen (and flickers) every time you press ↑/↓ — only the highlight moves.
- **Flicker-free arrow navigation (Windows).** Moving the selection now rewrites just the two affected rows in place instead of clearing and redrawing the entire screen. The full redraw is reserved for real view changes (switching tab, searching, paging, returning from preview).
- macOS/Linux already redrew without flicker (curses diff-based rendering); no change needed there.

## 1.7.3
**Plain summary:** moving between entries in `claude -h` is now smooth — no more pause when you scroll to a session you haven't viewed yet.
- **Faster, bounded reading.** Each entry's title/device/message-count is read with a quick line-capped scan (JSON parsing only on lines that need it) instead of reading the whole file. On a 74 MB session this dropped first-view scan time from ~560 ms to ~80 ms.
- Very large sessions show their message count as e.g. `4000+` (capped) rather than stalling to count every line. Results are still cached, so revisiting an entry is instant.

## 1.7.2
**Plain summary:** `claude -h` gained a search box at the top (filters as you type) and a roomier two-line layout for each entry.
- **Bordered search box** at the very top — just start typing to filter live; Backspace edits, Esc clears (or quits when empty).
- **Two-line entries with a divider**: line 1 is the title; line 2 is *device · message count · time · project* — easier to scan.
- **Space** previews a session's contents; **Enter** resumes.

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
