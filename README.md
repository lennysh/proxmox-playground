# proxmox-playground

Bash scripts and utilities for Proxmox administration. Each collection is self-contained with its own README, scripts, and documentation.

**Repository:** [github.com/lennysh/proxmox-playground](https://github.com/lennysh/proxmox-playground)

## Collections

| Collection | Description | Documentation |
|------------|-------------|---------------|
| [docker-zvol](docker-zvol/) | ZFS zvol storage for Docker in LXC containers | [README](docker-zvol/README.md) · [Guide](docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md) · [Quick ref](docker-zvol/docs/QUICK_REFERENCE.sh) |
| [vm-import](vm-import/) | Import qcow2/raw/vmdk disks into Proxmox VMs on ZFS | [README](vm-import/README.md) |
| [backup-summary](backup-summary/) | Summarize vzdump task logs for failures and incomplete jobs | [README](backup-summary/README.md) |

Pick a collection, open its README, and follow the quick start there.

## Repository layout

```
proxmox-playground/
├── README.md              # This file
├── CONTRIBUTING.md        # How to add collections
├── docs/
│   ├── FILE_INDEX.md      # File-by-file navigation
│   └── PROJECT_SUMMARY.md # Collections overview
├── docker-zvol/
├── vm-import/
└── backup-summary/
```

## Other documentation

- [FILE_INDEX.md](docs/FILE_INDEX.md) — find any file in the repo
- [PROJECT_SUMMARY.md](docs/PROJECT_SUMMARY.md) — brief overview of all collections
- [CONTRIBUTING.md](CONTRIBUTING.md) — add scripts or new collections

## General notes

- Most host-side scripts require **root** on a Proxmox node and **PVE 7+**.
- Scripts that modify the system support **dry-run** (`-d`) where applicable — use it first.
- Collection-specific requirements, options, and examples live in each collection's README.

## Contributing

Contributions and new collections are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

These scripts are provided as-is for Proxmox administration and use.
