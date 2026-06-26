# proxmox-playground — Project Summary

Overview of the script collections in this repository.

## Collections

| Collection | Purpose | Key script(s) |
|------------|---------|---------------|
| [docker-zvol](../docker-zvol/) | ZFS zvol storage for Docker in LXC containers | `setup-docker-zvol.sh`, `manage-docker-zvols.sh`, `zvol-utilities.sh` |
| [vm-import](../vm-import/) | Import qcow2/raw/vmdk disks into Proxmox VMs on ZFS | `import-qcow2-zfs.sh` |
| [backup-summary](../backup-summary/) | Summarize vzdump task logs (failures, incomplete jobs) | `summarize-vzdump-log.sh` |

Each collection is self-contained with its own README, scripts, and (where applicable) examples and docs.

## Repository layout

```
proxmox-playground/
├── README.md                 # Start here
├── CONTRIBUTING.md           # How to add collections
├── docs/
│   ├── FILE_INDEX.md         # File-by-file navigation
│   └── PROJECT_SUMMARY.md    # This file
├── docker-zvol/              # Docker zvol management
├── vm-import/                # VM disk import
└── backup-summary/           # vzdump log summaries
```

## Quick links

- **New to the repo?** Read [README.md](../README.md), then open the README for the collection you need.
- **Find a specific file?** See [FILE_INDEX.md](FILE_INDEX.md).
- **Add a script or collection?** See [CONTRIBUTING.md](../CONTRIBUTING.md).

### docker-zvol highlights

- One zvol per LXC container for isolation, snapshots, and independent sizing.
- Expand zvols in production with no downtime (`zvol-utilities.sh expand`).
- Batch setup via `examples/docker-zvols.conf`.
- Deep dive: [DOCKER_ZVOL_MANAGEMENT.md](../docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md).

### vm-import highlights

- Import qcow2, raw, or vmdk images to ZFS-backed Proxmox storage.
- Dry-run mode, optional VM creation, optional boot-disk setup.

### backup-summary highlights

- Parse Proxmox vzdump task logs for failed or incomplete backups.
- `--errors-only` for compact output; exit code 2 when problems are found.

## Shared conventions

All collections follow the same patterns where applicable:

- Bash with `set -euo pipefail`
- `-h` / `--help` on scripts
- Dry-run mode (`-d`) when modifying the system
- Root checks and input validation on host-side operations

---

**Last Updated**: 2026-06-26
