# Sync providers

`claude-session-sync` is agnostic to *how* files are synced — it only needs a folder that
your sync tool keeps in sync across machines. `detect-sync` auto-discovers common ones.

| Provider | Typical root | Notes |
|---|---|---|
| **Syncthing** | configured folder paths | Best for large/real-time peer-to-peer sync. Enable **File Versioning** for backups. |
| **iCloud Drive** | macOS: `~/Library/Mobile Documents/com~apple~CloudDocs` · Windows: `%USERPROFILE%\iCloudDrive` | Files may be evicted ("optimize storage"); keep `_ClaudeCode` downloaded. |
| **Dropbox** | `~/Dropbox` | Smart Sync can evict files — mark as "available offline". |
| **OneDrive** | `%OneDrive%` / `~/OneDrive*` | Disable Files-On-Demand eviction for `_ClaudeCode`. |
| **Google Drive** | `~/Google Drive` or `~/Library/CloudStorage/GoogleDrive*` | Use mirror (not stream) mode. |

## Recommendations
- Pick **one** sync folder that already replicates to every device.
- Turn on the provider's **version history / file versioning** — transcripts are append-heavy
  and versioning gives you a real backup against accidental deletion or sync conflicts.
- **Never** run Claude Code on the *same project* on two machines at once. Per-project locking
  enforces this when you use `cc` or the auto-lock hooks.

## Conflicts
If two machines write the same `.jsonl` simultaneously, most providers create a
`*.sync-conflict-*` (Syncthing) or `*(conflicted copy)*` (Dropbox) file. Locking prevents
this; if you ever see one, the lock was bypassed — close one side and reconcile manually.
