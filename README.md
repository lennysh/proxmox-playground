# proxmox-playground

A collection of useful bash scripts and utilities for Proxmox administration.

**Repository:** [github.com/lennysh/proxmox-playground](https://github.com/lennysh/proxmox-playground)

## 📁 Repository Structure

```
proxmox-playground/
├── README.md                           # This file
├── docs/                               # Root-level documentation
│   ├── FILE_INDEX.md                   # Navigation guide
│   └── PROJECT_SUMMARY.md              # Overall project info
├── docker-zvol/                        # Docker Storage Management
│   ├── README.md                       # Docker-zvol specific docs
│   ├── scripts/                        # Executable scripts
│   │   ├── setup-docker-zvol.sh
│   │   ├── manage-docker-zvols.sh
│   │   └── zvol-utilities.sh
│   ├── examples/                       # Configuration templates
│   │   └── docker-zvols.conf
│   └── docs/                           # Docker-zvol documentation
│       ├── DOCKER_ZVOL_MANAGEMENT.md
│       └── QUICK_REFERENCE.sh
├── vm-import/                          # VM Disk Import
│   ├── README.md                       # VM-import docs
│   └── scripts/
│       └── import-qcow2-zfs.sh         # Import qcow2 to ZFS
└── backup-summary/                     # vzdump log summaries
    ├── README.md
    ├── scripts/summarize-vzdump-log.sh
    └── example-logs/                   # sample task logs
```

## 🚀 Quick Start

### Docker ZVol Management
Setup Docker storage in ProxMox LXC containers using ZFS zvols:

```bash
cd docker-zvol

# Single container setup (5 minutes)
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G

# Multiple containers from config (10 minutes)
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf

# Monitor and manage
sudo ./scripts/zvol-utilities.sh monitor rpool 5
```

See [docker-zvol/README.md](docker-zvol/README.md) for complete documentation.

### VM Import (QCOW2 to ZFS)
Import qcow2 disk images into Proxmox VMs on ZFS storage:

```bash
cd vm-import

# Import to VM 100
sudo ./scripts/import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2

# Import and set as boot disk
sudo ./scripts/import-qcow2-zfs.sh -v 101 -i ./debian.qcow2 --boot
```

See [vm-import/README.md](vm-import/README.md) for complete documentation.

### Backup Log Summary
Summarize Proxmox vzdump task logs to find failed or incomplete backups:

```bash
cd backup-summary

# Full summary
./scripts/summarize-vzdump-log.sh /path/to/task-UPID.log

# Compact: failures and job result only
./scripts/summarize-vzdump-log.sh --errors-only /path/to/task-UPID.log
```

See [backup-summary/README.md](backup-summary/README.md) for complete documentation.

## 📚 Collections

### [docker-zvol](docker-zvol/) - Docker Storage Management
Automate creation and management of ZFS zvols for Docker storage in LXC containers.

**Includes:**
- Setup script for single containers
- Batch setup for multiple containers
- Monitoring and maintenance utilities
- Comprehensive documentation
- Configuration templates

**Key Features:**
- ✅ Automated zvol creation and formatting
- ✅ Expansion without downtime
- ✅ Real-time monitoring
- ✅ Snapshot management
- ✅ Production-ready with safety features

**Documentation:**
- [Docker-zvol README](docker-zvol/README.md) - Overview and quick start
- [DOCKER_ZVOL_MANAGEMENT.md](docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md) - Technical guide
- [QUICK_REFERENCE.sh](docker-zvol/docs/QUICK_REFERENCE.sh) - Command reference

### [vm-import](vm-import/) - VM Disk Import
Import qcow2/raw/vmdk disk images into Proxmox VMs on ZFS storage.

**Includes:**
- import-qcow2-zfs.sh - Import disk images to ZFS-backed VMs
- Dry-run mode and validation
- Optional VM creation
- Boot disk configuration

**Key Features:**
- ✅ QCOW2, raw, and VMDK support
- ✅ Automatic ZFS zvol creation
- ✅ Automatic disk attachment
- ✅ Safety checks and confirmations

**Documentation:**
- [vm-import/README.md](vm-import/README.md) - Overview and usage

### [backup-summary](backup-summary/) - vzdump Log Summary
Parse Proxmox vzdump task logs for failed backups, incomplete VMs, and job errors.

**Includes:**
- summarize-vzdump-log.sh - Parse and summarize task logs
- example-logs/ - Sample logs for testing

**Key Features:**
- Detects definitive backup failures and incomplete jobs
- Compact `--errors-only` mode for scripts and cron
- Optional `--warnings` for non-fatal ERROR lines
- Exit code 2 when problems are found

**Documentation:**
- [backup-summary/README.md](backup-summary/README.md) - Overview and usage

### Future Collections
More script collections may be added for:
- LXC container management
- Monitoring and alerting
- Networking utilities
- Storage management
- System administration

## 📖 Documentation

### Root Level Documentation
- **[FILE_INDEX.md](docs/FILE_INDEX.md)** - Navigation guide for all files
- **[PROJECT_SUMMARY.md](docs/PROJECT_SUMMARY.md)** - Overall project information

### Collection-Specific Documentation
Each collection has its own README:
- [docker-zvol/README.md](docker-zvol/README.md) - Docker ZVol overview
- [docker-zvol/docs/](docker-zvol/docs/) - Detailed guides and references
- [vm-import/README.md](vm-import/README.md) - VM disk import
- [backup-summary/README.md](backup-summary/README.md) - vzdump log summaries

## 🎯 Common Tasks

### Docker Storage

**Setup a single container with Docker storage:**
```bash
cd docker-zvol
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 50G
```

**Setup multiple containers from config:**
```bash
cd docker-zvol
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf
```

**Monitor zvol usage in real-time:**
```bash
cd docker-zvol
sudo ./scripts/zvol-utilities.sh monitor rpool 5
```

**Expand a zvol (no downtime):**
```bash
cd docker-zvol
sudo ./scripts/zvol-utilities.sh expand 100 rpool docker_app1 100G
```

**Import qcow2 disk to VM:**
```bash
cd vm-import
sudo ./scripts/import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2
```

**Summarize a vzdump task log:**
```bash
cd backup-summary
./scripts/summarize-vzdump-log.sh --errors-only /path/to/task-UPID.log
```

**Get help:**
```bash
cd docker-zvol
./scripts/setup-docker-zvol.sh -h
./scripts/manage-docker-zvols.sh -h
./scripts/zvol-utilities.sh help

cd vm-import
./scripts/import-qcow2-zfs.sh -h

cd backup-summary
./scripts/summarize-vzdump-log.sh --help
```

## 🔧 Requirements

All scripts require:
- ProxMox 7.0+ or 8.0+
- Root access on ProxMox host
- Bash 4.0+
- Standard Linux utilities: zfs, mkfs.ext4, pct, chown, etc.

Collection-specific requirements are listed in their README files.

## 💡 Features

### Safety First
- ✅ Dry-run mode for all scripts (`-d` flag)
- ✅ Automatic configuration backups
- ✅ Full input validation
- ✅ Confirmation prompts for destructive operations
- ✅ Error recovery and logging

### Automation
- ✅ Single script execution for simple tasks
- ✅ Batch operations via configuration files
- ✅ Reusable command templates
- ✅ Integration-friendly design

### Documentation
- ✅ Comprehensive README files
- ✅ Inline script documentation
- ✅ Quick reference guides
- ✅ Examples and use cases

### Monitoring
- ✅ Real-time usage dashboards
- ✅ Status reporting
- ✅ Performance metrics
- ✅ Alert capabilities

## 📝 Scripts Overview

### docker-zvol

| Script | Purpose |
|--------|---------|
| `setup-docker-zvol.sh` | Create and configure a zvol for one LXC container |
| `manage-docker-zvols.sh` | Batch setup from a config file |
| `zvol-utilities.sh` | Monitor, expand, and snapshot zvols |

### vm-import

| Script | Purpose |
|--------|---------|
| `import-qcow2-zfs.sh` | Import qcow2/raw/vmdk disk images to ZFS-backed VMs |

### backup-summary

| Script | Purpose |
|--------|---------|
| `summarize-vzdump-log.sh` | Summarize vzdump task logs for failures and job status |

## 🛠️ Development

### Adding New Script Collections

To add a new collection:

1. Create a new directory: `mkdir -p my-collection/{scripts,examples,docs}`
2. Add your scripts to `scripts/`
3. Add templates to `examples/`
4. Add documentation to `docs/`
5. Create `my-collection/README.md` with overview
6. Update root README.md with the new collection

### Script Template

```bash
#!/bin/bash

################################################################################
# Script Name
# Brief description of what the script does
################################################################################

set -euo pipefail

# ... script content ...
```

## ⚠️ Important Notes

- **Always test with dry-run mode first**: `-d` flag
- **Back up your configurations**: Automatic backups are created
- **Read the documentation**: Each collection has comprehensive guides
- **Check requirements**: Ensure your ProxMox version and tools are compatible
- **Report issues**: Share improvements and bug reports

## 📄 License

These scripts are provided as-is for ProxMox administration and use.

## 🤝 Contributing

Contributions, improvements, and new script collections are welcome!

## 📞 Support

For each collection:
1. Read the collection's README
2. Check the collection's documentation
3. Review script help: `./script.sh -h`
4. Check QUICK_REFERENCE guides

## 🗺️ Roadmap

Planned future collections:
- [ ] LXC container utilities (create, clone, backup)
- [ ] Storage management (pool, backup, quotas)
- [ ] Monitoring and alerting
- [ ] Network configuration
- [ ] VM management utilities

---

**Last Updated**: 2026-06-26  
**Status**: Active Development

For the latest updates, see individual collection README files.
