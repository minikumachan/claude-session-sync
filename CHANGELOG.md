# Changelog

**English** | [日本語 (CHANGELOG.ja.md)](CHANGELOG.ja.md) · This project follows [Semantic Versioning](https://semver.org/).

> **In plain words — what this tool does today:** shares your Claude Code history across your
> computers (or syncs it itself via GitHub if you have no sync app), stops two machines from
> editing the same project at once, and adds **`claude -h`** to browse all your history while
> leaving the official **`claude -r`** untouched. Each version's first line below is a plain summary;
> the bullets are the details.

## 1.23.1
**Plain summary:** MCP sharing now explains itself instead of looking broken. It aggregates MCP servers from **all scopes** (user + per-project), and tells you clearly that **claude.ai connectors are account-level** (synced by logging into claude.ai, not file-shareable).
- Cause: MCP sharing only read the **top-level** `mcpServers` in `~/.claude.json`. But `claude mcp add` saves to the **project (local) scope** by default (`projects[<cwd>].mcpServers`), so the top level is usually empty → Export found nothing → no `servers.json` → Import said "definition not found" (read as "json not defined"). Separately, most users' MCPs are **claude.ai connectors** (Notion/Canva/Figma/…), which live in the claude.ai account, not in a local file at all.
- Fix: `mcp-sync` now **aggregates** servers from the user scope **and** every `projects[*].mcpServers` (deduped by name), so locally-added servers are actually found and exported (imported back at user scope = available everywhere).
- Clear guidance: Status/Export/Import now show the **count per source**, list your **claude.ai connectors** by name (from `claudeAiMcpEverConnected`), and state that those sync via claude.ai login (no file-sharing needed). The "nothing to share / file not found" cases now print a helpful explanation instead of a bare error.
- Windows + macOS/Linux (`mcp-sync.ps1` / `mcp-sync.sh`). Verified against real data: local count 0, connectors listed (Context7, Notion, Gamma, Figma, Canva), no crash.

## 1.23.0
**Plain summary:** short launch shortcuts **`c` / `cfp` / `ch` / `ca`** in every shell, a **fixed-folder launch** (`cfp`) you set with a native folder dialog, **remote-control auto-ON** re-implemented with per-launch-method toggles, and a **base-language** setting — all configurable from `claude -a`.
- Shortcuts (installed by `install-shell-wrap`, work in PowerShell / cmd.exe / Git Bash / bash / zsh via functions + doskey, which outrank PATH): **`c`** = launch claude in the current folder, **`cfp`** = launch in a fixed folder, **`ch`** = history UI (`claude -h`), **`ca`** = settings (`claude -a`). `cp` was avoided because it's the file-copy command in every shell; `-p` (Claude's print flag) is unrelated, so `cfp` is a dedicated interactive launcher, not `claude -p`.
- Fixed-folder launch (`cfp`): set the folder from **`claude -a` → 起動ショートカット設定** using a **native folder picker** (Explorer's `BrowseForFolder` on Windows, `choose folder`/zenity/kdialog on macOS/Linux). `cfp` then starts claude in that folder regardless of your current directory.
- Remote control on launch (re-implemented): `c` and `cfp` add `--remote-control` so the session is phone-controllable. It's a **per-launch-method toggle** in `claude -a` (c / cfp independently; default ON). The raw `claude` passthrough is left untouched so `claude -p` and scripting aren't affected. (Auto-start entries keep their own per-entry remote setting.)
- Base language: **`claude -a` → 基本言語** sets `lang` and ties **`titleLang`** to it, so auto-titles — and re-titling when a conversation is continued/migrated to another device — use your chosen language (auto / ja / en / zh / ko / es / fr / de / pt / ru). `auto` keeps matching each conversation's own language.
- Shared launcher `cgo.ps1` / `cgo.sh` centralizes the shortcut logic (reads config, resolves the real claude excluding the shim dir, applies the remote flag / fixed path). Config keys added: `launchPath`, `remoteC`, `remoteCfp` (written safely, preserving existing keys).
- Verified: c/cfp/ch/ca defined in PowerShell, cmd.exe (doskey) and Git Bash; `c --version` / `cfp --version` resolve the real CLI with `--remote-control` prepended; config read/write roundtrips the new keys without dropping existing ones; base-language cycle updates lang+titleLang.

## 1.22.2
**Plain summary:** cleaner, more compact `claude -h` rows — main vs subagent is distinguishable in **every** tab, and the long status phrases are replaced by short glyphs.
- Main vs sub: subagent rows are marked with **🤖** on both the title and the meta line (the meta's leading token is the device for main, `🤖<type>` for sub), so you can tell them apart in any tab, not just 全履歴.
- Compact status: the verbose bracketed phrases are gone. Now: **🔒**`<device>` = in use (locked), **🤖▶**`<device>` = a subagent is running under this main, **▶**`<parent>` = this subagent is running now, **←**`<parent>` = the main this subagent came from, `(自)` = this device. Color carries meaning (red = in use, yellow = running, dim = idle/origin).
- Meta fields tightened: `device · N msg · time · project` (mid-dots instead of pipes); subagent rows show `🤖type · device · time   ←/▶ parent`.
- A one-line legend at the bottom decodes the glyphs: `🤖サブ ▶実行中 🔒使用中 ←元会話`.
- macOS/Linux: row positioning now uses display-width (handles emoji/CJK columns) so the meta line doesn't drift.

## 1.22.1
**Plain summary:** fixes `claude -h` still showing the raw help text in **cmd.exe** and **Git Bash** (the v1.21.0 PATH-shim wasn't enough). It now intercepts via mechanisms that outrank PATH in every shell.
- Cause: on this setup the real `claude` lives in the **machine (system) PATH** (`…\AppData\Roaming\npm`), and Windows always places machine PATH **before** user PATH. So a user-PATH shim (`~/.claude/css-bin`) can never win — cmd.exe/Git Bash kept resolving npm's `claude.cmd` and printing `--help`.
- Fix: override with constructs that beat PATH lookup, per shell:
  - **PowerShell** — profile `claude` function (already; functions outrank PATH).
  - **cmd.exe** — a **doskey macro** `claude` defined via the Command Processor **AutoRun** key (`HKCU\Software\Microsoft\Command Processor`); doskey macros are expanded before PATH resolution for interactive input.
  - **Git Bash / MSYS** — a `claude()` function in `~/.bashrc` (functions outrank PATH).
  - All three call the shared `~/.claude/css-bin` shims, so routing logic stays in one place; pass-through still resolves the real `claude` (excluding the shim dir).
- Uninstall (`-Uninstall`) now also removes the doskey macro from AutoRun and the `~/.bashrc` block. **Open a brand-new terminal** after install — AutoRun/profile/rc only apply to newly-started shells; already-open windows keep the old behavior.
- Note: the cmd.exe doskey macro applies to **interactive** Command Prompt input (typing `claude -h`), not to `cmd /c "claude …"` inside scripts (those still hit the real CLI, which is correct for scripting).

## 1.22.0
**Plain summary:** new **アクセス中 (in-use) tab** in `claude -h` lets you **disconnect a stale lock from any device** (so a conversation left open on another machine no longer blocks you) — and it **refuses to disconnect while that conversation is actually running**. Main vs subagent rows are now marked with **🤖**, and a **check-deps doctor** verifies required tools at install/first-run.
- Remote disconnect: every conversation's "in use (アクセス中)" state comes from a lock file in `<share>/locks/*.lock` (`session=<sid>`). The new tab lists exactly those. From the in-use tab, the launch warning, or the Tab action-menu you can **切断 (disconnect)** = delete that lock so this device can open the conversation. Works from any device to any device, whether the other machine is on or off.
- Running guard: disconnect is **blocked** when the conversation looks actively running — defined as its transcript `.jsonl` (newest copy across folders, i.e. the synced one) having been modified within `lockLiveWin` seconds (default 90; configurable in `session-sync.local.conf`). Idle/closed/crashed locks (no recent update) are disconnectable after a confirmation that warns about `.sync-conflict` risk if the other side is still open. (There is no official "is-running" flag with file-sync, so this is a freshness approximation, bounded by sync latency — the safest fully-reliable disconnect is still when the other machine has closed the conversation.)
- 🤖 main/subagent distinction: in 全履歴 (and the サブ tab) subagent rows are prefixed with **🤖** so they're instantly distinguishable from main-agent rows when the two are interleaved by time. Tabs were renamed メインエージェント→**メイン** / サブエージェント→**サブ** so the new 6th tab (アクセス中) fits on an 80-column terminal.
- Onboarding / dependencies: new **`check-deps.ps1` / `check-deps.sh`** report whether the required tools are present — Windows: PowerShell (built-in; pwsh recommended) + the `claude` CLI; macOS/Linux: **python3 + curses** (curses is in the stdlib, present by default) + `claude`; git is optional (git-transport only). They're run by `install.ps1`/`install.sh`, surfaced from the `claude -a` settings menu (環境チェック), and `claude -h` on macOS/Linux now runs the doctor with install guidance (brew/apt/dnf/pacman, optional auto-install with confirmation) instead of a terse "python3 が必要です". Installers also now offer to set up the shell integration automatically.
- Verified on real data (both Windows ps1 and macOS/Linux sh code paths): 全履歴 814 / メイン 594 / サブ 220 / アクセス中 1; the in-use entry is the live current session, correctly reported as running (so it would be protected from disconnect).

## 1.21.0
**Plain summary:** `claude -h` (and `claude -a`) now work from **any shell** — PowerShell, **cmd.exe**, and **Git Bash** on Windows, plus bash/zsh on macOS/Linux. Previously, outside a profile-loaded PowerShell, `claude -h` printed Claude's raw usage/help text (a wall of `--flags` and `<json>` examples that looks like code) instead of the history browser.
- Cause: the integration only added a `claude` **function** to the PowerShell profile / `~/.bashrc` / `~/.zshrc`. That can't cover **cmd.exe** at all (no function mechanism), and misses any shell whose init file isn't loaded (e.g. `pwsh -NoProfile`, a fresh terminal, Git Bash where the wrapper was never installed). In those cases `claude -h` reached the real CLI, whose `-h` is `--help` → the usage dump the user saw as "code-like text".
- Fix: `install-shell-wrap` now also installs **cross-shell PATH shims** (the nvm/pyenv pattern). It creates a device-local `~/.claude/css-bin/` with `claude.cmd` (cmd.exe), `claude.ps1` (pwsh without profile), and `claude` (Git Bash/MSYS · macOS/Linux), and prepends that dir to PATH. Each shim intercepts `-h`/`--history` and `-a`/`--autostart`, and passes **everything else straight through to the real `claude`** (resolved from PATH excluding the shim dir, so no recursion). The PowerShell/bash/zsh function is still installed too (belt-and-suspenders: it intercepts fastest when the profile is loaded).
- Windows PATH is updated **safely**: written via the registry as `REG_EXPAND_SZ` (preserving `%VAR%` entries — `[Environment]::SetEnvironmentVariable` would downgrade them to `REG_SZ`), and a `WM_SETTINGCHANGE` broadcast lets newly-opened terminals pick up the new PATH without re-login.
- Encoding: the Windows history/settings UIs now force the console to UTF-8 at startup (`[Console]::OutputEncoding`, which also sets the console code page) and restore it on exit, so Japanese, box-drawing (`─│┌`) and `★` render correctly even when launched as a fresh process from cmd.exe/Git Bash or on a CP932-default machine.
- On Windows, Git Bash routes `-h` to the PowerShell UI (Windows Python has no `curses`); on macOS/Linux the shim runs the curses UI directly. Pass-through (`claude`, `claude -r`, `claude --resume`, `--version`, …) is unchanged. Uninstall (`-Uninstall` / `--uninstall`) removes the function, the shims, and the PATH entry.
- Verified on this machine: pass-through returns the real CLI from cmd.exe and Git Bash; `claude -h` no longer prints "Usage: claude" in cmd.exe / Git Bash / `pwsh -NoProfile`; the UI `-SelfTest` renders clean Japanese + borders.

## 1.20.1
**Plain summary:** the same conversation no longer appears twice in `claude -h` (incl. Favorites), and each row now shows the **latest** copy.
- Cause: a conversation resumed in another folder or on another device is copied to the current folder (and synced back), so the **same sid exists as `.jsonl` in multiple project folders**. The lists showed each copy separately, and Favorites (a set of sids) therefore rendered the same conversation multiple times — including stale older copies.
- Fix: every list now **de-duplicates by sid, keeping the newest (max mtime) copy**. Lists are already time-ordered, so the first occurrence (newest) is kept. Favorites/全履歴/メインエージェント now show one entry per conversation with its latest title, time and folder. (このプロジェクト was already unique per folder; subagents are unaffected.)
- Verified on real data: 2 cross-device duplicate conversations collapse to 1 each (newest kept); メインエージェント 496→494 with 0 duplicate sids. Windows + macOS/Linux.

## 1.20.0
**Plain summary:** reworks the `claude -h` tabs to **全履歴 / このプロジェクト / お気に入り / メインエージェント / サブエージェント**, adds **page prev/next buttons + jump-to-page**, and fixes the **broken Favorites layout**.
- **Tabs**: 全履歴 now shows **everything** (main conversations + subagents) in one time-ordered list; メインエージェント is main-only; サブエージェント is subagents-only; このプロジェクト / お気に入り filter main conversations. (The old 最近7日 tab was dropped.) The 全履歴 tab renders each row by its real kind, so main and subagent rows keep their own markers.
- **Pagination controls**: the info line now shows `< 前 ／ ページ X/Y ／ 次 >` buttons plus a hint. `PgUp/PgDn` switch pages (as before, now surfaced as buttons); **`Ctrl+G`** opens a "jump to page number" prompt. On macOS/Linux the `< 前` / `次 >` buttons and the page number are **mouse-clickable** (the number opens the jump prompt).
- **Favorites UI fix**: the `★` marker (U+2605) is East-Asian *Ambiguous* width and renders as 2 columns in CJK terminals, but the width calc counted it as 1 → favorited rows overflowed by one column and the fixed-position redraw broke. `★`/`☆` are now counted as width 2 (safe over-estimate), so favorited rows no longer corrupt the layout.
- Windows (`history-ui.ps1`) and macOS/Linux (`history-ui.sh`) both updated; verified against real data (708 total = 496 main + 212 subagents; all-tab time-ordered; tab counts and width math checked).

## 1.19.0
**Plain summary:** `claude -h` now separates **subagent** history from main-agent history into its own **🤖サブエージェント** tab, and shows live "running" state. When no device is in a conversation but one of its subagents is running, the main row shows `[<device> でサブエージェント実行中（このデバイス）]`; when neither, it shows nothing. Subagent rows show which main agent / source device they belong to and whether they're running now.
- **New tab 🤖サブエージェント**: lists `…/<mainSession>/subagents/agent-*.jsonl` transcripts (previously hidden). Each row shows `🤖 <agentType>` (from `attributionAgent`), the first task prompt as the title, and a marker `[実行中 ← 「<main title>」メインから ・ 実行元: <device>（このデバイス）]` when running, or `[元: 「<main title>」 ・ <device>]` otherwise. Enter / click / Tab→"open parent" jumps to the **parent main conversation** (subagents aren't independently resumable); Space previews the subagent transcript.
- **Main rows, 3-state presence**: ① a device holds the conversation (lock) → `[アクセス中: <device>]` (existing); ② no lock **and** a subagent is running → `[<device> でサブエージェント実行中]`; ③ neither → nothing.
- **Running detection**: a subagent counts as "running" if its transcript was written within the last `subRunWin` seconds (default **120**, configurable in `session-sync.local.conf`). There is no official subagent lock, so transcript freshness is the signal — accuracy is bounded by file-sync latency. Cross-device via the shared folder; main tabs refresh subagent state on a 5s timer (Windows) / 1.5s redraw with a 5s cache (macOS/Linux).
- **This-device marker** is now robust to both device-name forms (lock `COMPUTERNAME`/`hostname` and path-derived `Win/<user>`·`Mac/<user>`), so `（このデバイス）` shows correctly regardless of which form a record uses.
- Windows (`history-ui.ps1`) and macOS/Linux (`history-ui.sh`) both updated; verified against real transcripts (212 subagent files) on both code paths.

## 1.18.3
**Plain summary:** fixes garbled Japanese (mojibake like `���̃v���W�F�N�g`) in the SessionStart hook messages — the "this project may be in use on another device" lock warning and the device-switch notice. They now render correctly in Claude's context.
- Cause: on Windows PowerShell 5.1 the default console output encoding is the OEM code page (CP932 on a Japanese system), so `Write-Output` emitted CP932 bytes while Claude reads hook stdout as UTF-8 → mojibake. The script source was fine (BOM-encoded); only the *output byte stream* was wrong.
- Fix: both SessionStart hooks (`hook-lock.ps1` acquire, `hook-devswitch.ps1`) now write their messages as UTF-8 bytes straight to stdout via a `CssEmit` helper, independent of the console code page — symmetric with the existing UTF-8 `OpenStandardInput` reader used for stdin.
- Verified by reproducing the exact failing condition (forced CP932 output): old `Write-Output` produced `OLD:���̃v���W�F�N�g` (U+FFFD present, matching the reported symptom), new `CssEmit` produced clean `このプロジェクト`.

## 1.18.2
**Plain summary:** fixes a runtime error ("'if' is not recognized…") in `claude -h` when you choose **`[r]` resume with a changed permission** — the permission picker failed to draw and the screen errored out.
- Cause: the picker's draw line used `( if(...){…}else{…} )` as an expression. PowerShell does not allow an `if` **statement** inside `( )` grouping — it needs the subexpression operator `$( )`. Changed to `$(if…)`.
- This was a runtime-only error, so token-level syntax checks and `-SelfTest` (which renders the list, not the interactive sub-screen) didn't catch it; it surfaced only on opening the permission picker. Swept all `.ps1` for the same `(if…)`/`(switch…)` grouping mistake — this was the only instance.

## 1.18.1
**Plain summary:** makes `claude -h` arrow navigation light again. Moving the selection now repaints **only the two affected title rows** (a full repaint is reserved for tab/search/page/resize/returning from a sub-screen), so focus movement is snappy; the history list still loads once at startup.
- Wrapping is already eliminated (display-width clipping + full-width overwrite), so the fixed-position partial update (`Y=6+item*3`) can't drift (the wrapping that broke 1.17.x is gone).
- When the in-use device is **this machine**, the marker shows `[in use: <device>（このデバイス）]` and the in-use warning says it's open in another window/tab on this device. (Windows + macOS/Linux.)

## 1.18.0
**Plain summary:** `claude -h` no longer flickers when you move the selection. Instead of clearing the whole screen each frame, it homes the cursor and overwrites every line in place (padding to full width and clearing only the rows below). `Clear-Host` now runs only on first paint and on resize/tab-switch, so arrow navigation is flicker-free — while keeping the corruption-proof full repaint from 1.17.3.
- Each line is overwritten to full width (screen width − 1) by display width, so there are no leftovers and no wrapping. No VT escape codes (safe on Windows PowerShell 5.1). No newlines emitted, so the buffer never scrolls.
- The selected row is highlighted full-width. In-use locks are re-read only on full-clear frames (arrow moves do no extra IO); freshness is handled by the live-refresh timer.

## 1.17.3
**Plain summary:** fixes `claude -h` arrow-navigation corruption where colors vanished and meta lines got overwritten by titles. Removed the fixed-position partial redraw; the list now **fully repaints on every move** (no drift regardless of terminal/width).
- The partial redraw wrote to fixed rows (`Y=6+item*3`) assuming exactly 3 lines per item; if any line (search box / meta) wrapped, positions drifted and titles overwrote the colored meta line. Removed.
- Trade-off: a slight flicker may appear when moving the selection (correctness prioritized); a double-buffered version can be added if needed.
- macOS/Linux (curses) was unaffected (it manages its own screen buffer).

## 1.17.2
**Plain summary:** fixes `claude -h` where Japanese titles wrapped onto two lines and arrowing down corrupted the colors/text without recovering.
- Cause: titles were truncated by **character count**, so full-width (display-width-2) Japanese titles overflowed the screen width and **wrapped**, making each item taller than its assumed 3 lines and throwing off the fixed-position partial redraw.
- Fix: truncate the title and meta line by **display width** (no wrapping); ASCII `> ` selection marker (avoids ambiguous-width `❯`); cap the meta line to the screen width and render the in-use marker as `[in use: …]` (no box-drawing/●, so width is measured correctly).

## 1.17.1
**Plain summary:** the `claude -h` in-use indicator now **updates live** — without pressing a key, it re-reads locks every few seconds, so starting/ending a conversation on another device lights up / clears the marker in **near real time** (bounded by your folder-sync latency).
- ps1: the non-blocking wait loop re-reads locks every ~3s and redraws when the in-use set changes.
- sh (curses): `getch` gets a 1.5s timeout for periodic redraws; single-key prompts (preview / permission confirm / in-use warning) were fixed to wait for a real key so the timeout doesn't dismiss them.
- Because this rides file sync, cross-device updates are limited by the sync app's propagation speed (not instant).

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
