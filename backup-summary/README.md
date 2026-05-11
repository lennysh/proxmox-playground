# Backup log summary

Summarize Proxmox **vzdump** task logs so you can see which guests failed without scrolling through progress lines.

## Script

```bash
./scripts/summarize-vzdump-log.sh /path/to/task-UPID.log
```

### Options

| Option | Description |
|--------|-------------|
| `--errors-only`, `-e` | Compact output: failures, incomplete VMs, job result |
| `--warnings`, `-w` | Also list other `ERROR:` lines with line numbers (often non-fatal, e.g. guest fs-freeze) |

### What it detects

- **Failed backups**: lines like `ERROR: Backup of VM 9000 failed - ...` (definitive vzdump failures)
- **Incomplete**: VM had `Starting Backup` but no `Finished` and no explicit failure (truncated log or crash)
- **Job status**: `Backup job finished with errors` and `TASK ERROR:`

Exit code **2** if there were failures, incomplete backups, or `TASK ERROR:`.

## Example

```bash
./scripts/summarize-vzdump-log.sh example-logs/task-lcspveh01-vzdump-2026-03-18T04_00_03Z.log
```

Example logs live under `example-logs/` for testing.
