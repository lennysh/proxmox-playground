# backup-tags

Proxmox backup jobs **cannot select guests by tag**. This collection rewrites an
existing Datacenter → Backup job from VM/CT tags: back up everything unless it
is tagged to opt out, and optionally control vzdump mode (`snapshot` / `suspend`
/ `stop`) with tags.

## Can the API see guests on every cluster node?

**Yes.** You do not query each node.

| Endpoint | What you get |
|----------|----------------|
| `GET /cluster/resources?type=vm` | Every QEMU VM and LXC in the cluster, including **node**, **vmid**, **name**, **tags**, **template** |
| `GET /cluster/backup` | All vzdump jobs (cluster config in pmxcfs, not per-node) |
| `GET /cluster/backup/{id}` | One job (schedule, storage, `all`/`exclude`/`vmid`, `mode`, …) |
| `PUT /cluster/backup/{id}` | Update that job |

Guest configs (and therefore tags) live in the clustered filesystem. Calling
the API on **any** node, or remotely with a token, is enough even when VMs are
spread across the cluster. A job with Node = `-- All --` still runs cluster-wide;
this script only changes **which VMIDs** that job includes.

What Proxmox **cannot** do natively is “include if tag X”. The UI “All except
9000,9001,…” list is exactly what this script maintains for you.

## Default policy

| Guest tag | Result |
|-----------|--------|
| *(none)* | **Back up**, mode **snapshot** |
| `no-backup` | **Skip** (added to the job’s exclude list) |
| `backup-snapshot` | Back up, mode snapshot |
| `backup-suspend` | Back up, mode suspend |
| `backup-stop` | Back up, mode stop |

All of those tag names, and the default mode, are configurable.

> **One mode per job.** vzdump `mode` is a single field on the job. Mixed
> snapshot/stop guests in **one** schedule will still all use that job’s mode
> (the script warns). Use `--selection include-mode` and **two jobs** if you
> need both.

## Quick start

On any cluster node (root, uses `pvesh`):

```bash
cd backup-tags

# Find the job id (the UUID shown is not in the screenshot table)
./scripts/sync-backup-job-from-tags.py --list-jobs

# See how every guest would be classified
./scripts/sync-backup-job-from-tags.py --report

# Plan: rewrite the job as "All except <no-backup VMIDs>"
./scripts/sync-backup-job-from-tags.py --job-id YOUR-JOB-ID

# Apply
./scripts/sync-backup-job-from-tags.py --job-id YOUR-JOB-ID --apply
```

Remote API (token):

```bash
cp examples/tag-backup.conf /root/tag-backup.conf
# set host, user, token_id, token_secret, job id
./scripts/sync-backup-job-from-tags.py --config /root/tag-backup.conf --apply --yes
```

Tag test VMs/CTs in the UI (Datacenter → Options → Tag Style is optional).
Then re-run the script (or a cron/timer) so the exclude list stays current.

With **`all-except`** (the default), **new untagged guests are backed up on the
next scheduled run without re-running this script**. Re-run when someone adds
or removes `no-backup` (or when you use `include-mode`).

## Directory structure

```
backup-tags/
├── README.md
├── scripts/sync-backup-job-from-tags.py
└── examples/tag-backup.conf
```

## Options

| Option | Description |
|--------|-------------|
| `--config`, `-c` | INI file (see `examples/tag-backup.conf`) |
| `--list-jobs` | Print job id, node, schedule, storage, selection, mode |
| `--report` | Classify all cluster guests; do not change a job |
| `--job-id` | Job to plan or update |
| `--selection all-except` | `all=1` + `exclude=` skipped VMIDs (default; matches “All except …”) |
| `--selection include-mode` | Explicit `vmid=` list for one resolved mode |
| `--mode snapshot\|suspend\|stop` | Mode to write / filter |
| `--sync-mode` / `--no-sync-mode` | Whether to set the job’s vzdump `mode` |
| `--exclude-tags` | Opt-out tags (default `no-backup`) |
| `--include-tags` | If set, guest must have at least one of these |
| `--apply` | Write the job (otherwise plan only) |
| `-d`, `--dry-run` | Plan only |
| `-y`, `--yes` | Skip the apply prompt |
| `--verbose` | Log API / pvesh calls |

Environment overrides: `PVE_HOST`, `PVE_USER`, `PVE_TOKEN_ID`,
`PVE_TOKEN_SECRET`, `PVE_PASSWORD`.

### Config file

See [examples/tag-backup.conf](examples/tag-backup.conf):

- `[api]` — host empty = `pvesh` on this node; otherwise HTTPS to `:8006`
- `[job]` — default job id, `selection`, `sync_mode`, `skip_templates`
- `[tags]` — exclude/include/mode tag names, `default_mode`, `conflict`

API token privileges: `Sys.Audit` + `Sys.Modify` on `/`, and `VM.Audit` (or
`VM.Backup`) so `/cluster/resources` can return guest names and tags.

## Mixed backup modes

```bash
# Job A: snapshot (untagged guests + backup-snapshot)
./scripts/sync-backup-job-from-tags.py --job-id nightly-snap \
  --selection include-mode --mode snapshot --apply

# Job B: only guests tagged backup-stop
./scripts/sync-backup-job-from-tags.py --job-id nightly-stop \
  --selection include-mode --mode stop --apply
```

`include-mode` writes an explicit VMID list, so **new guests are not picked up
until the script runs again**. Schedule it (cron / systemd timer), for example
hourly, well before the backup window.

## Requirements

- Proxmox VE 7+ (cluster-wide `/cluster/resources` tags; backup jobs in
  `/cluster/backup`)
- Python 3.9+ (stdlib only)
- On-node: `pvesh` as a user that can audit VMs and modify datacenter backup jobs
- Remote: API token or password; `verify_tls = false` is typical for the default
  PVE certificate

## See also

- [Root README](../README.md)
- [FILE_INDEX.md](../docs/FILE_INDEX.md)
- [Backup and Restore](https://pve.proxmox.com/pve-docs/chapter-vzdump.html)
