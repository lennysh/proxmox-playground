# docker-zvol

ProxMox Docker ZVol Management - Automate creation and management of ZFS zvols for Docker storage in LXC containers.

## Overview

This suite of scripts provides a complete solution for managing Docker storage in ProxMox LXC containers using ZFS zvols:

- **Isolation**: Each container gets its own dedicated zvol
- **Performance**: Independent I/O per container
- **Expansion**: Can grow storage without downtime
- **Backup**: Easy snapshotting per container
- **Monitoring**: Real-time usage tracking and alerts

## Quick Start

### Single Container (5 minutes)
```bash
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G -d
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G
```

### Multiple Containers (10 minutes)
```bash
nano examples/docker-zvols.conf           # Edit config
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf -d
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf
```

### Monitor & Maintain (Ongoing)
```bash
sudo ./scripts/zvol-utilities.sh list rpool              # List all zvols
sudo ./scripts/zvol-utilities.sh monitor rpool 5         # Live monitoring
sudo ./scripts/zvol-utilities.sh expand 100 rpool app 100G  # Expand (no downtime!)
```

## Directory Structure

```
docker-zvol/
├── scripts/                 # Executable scripts
│   ├── setup-docker-zvol.sh         # Setup single container
│   ├── manage-docker-zvols.sh       # Batch setup
│   └── zvol-utilities.sh            # Monitor & manage
├── examples/                # Configuration templates
│   └── docker-zvols.conf            # Example container config
└── docs/                    # Documentation
    ├── DOCKER_ZVOL_MANAGEMENT.md    # Technical guide
    └── QUICK_REFERENCE.sh           # Command reference
```

## Scripts

### `scripts/setup-docker-zvol.sh`
Setup a single LXC container with Docker zvol storage.

**Usage:**
```bash
sudo ./scripts/setup-docker-zvol.sh -c <container_id> -p <pool> -z <zvol_name> -s <size> [options]
```

**Options:**
- `-c, --container-id` (required): ProxMox container ID
- `-p, --pool` (required): ZFS pool name
- `-z, --zvol-name` (required): Name for the zvol
- `-s, --size` (required): Size (30G, 1T, 500M, etc.)
- `-d, --dry-run`: Preview without making changes
- `-v, --verbose`: Detailed output
- `-h, --help`: Show help

**Example:**
```bash
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_api_prod -s 50G
```

### `scripts/manage-docker-zvols.sh`
Batch setup multiple containers from a configuration file.

**Usage:**
```bash
sudo ./scripts/manage-docker-zvols.sh -c <config_file> [options]
```

**Options:**
- `-c, --config` (required): Configuration file path
- `-d, --dry-run`: Preview without making changes
- `-v, --verbose`: Detailed output
- `-y, --yes`: Skip confirmation prompts
- `-h, --help`: Show help

**Example:**
```bash
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf
```

### `scripts/zvol-utilities.sh`
Monitor, maintain, and manage zvols.

**Usage:**
```bash
sudo ./scripts/zvol-utilities.sh <command> [arguments]
```

**Commands:**
- `list [pool]` - List all docker zvols
- `status <zvol>` - Detailed zvol information
- `expand <cid> <pool> <zvol> <size>` - Expand zvol (no downtime!)
- `monitor [pool] [interval]` - Real-time monitoring
- `snapshot <zvol> [name]` - Create snapshot
- `snapshots-list <zvol>` - List snapshots
- `rollback <snapshot>` - Rollback to snapshot
- `disk-usage <cid> <mount>` - Check container disk usage
- `help` - Show help

**Examples:**
```bash
sudo ./scripts/zvol-utilities.sh list rpool
sudo ./scripts/zvol-utilities.sh status rpool/docker_app1
sudo ./scripts/zvol-utilities.sh expand 100 rpool docker_app1 100G
sudo ./scripts/zvol-utilities.sh monitor rpool 5
```

## Key Features

✅ **Automated Setup** - Creates zvol, formats ext4, sets permissions, adds to config  
✅ **Batch Operations** - Setup multiple containers from config file  
✅ **Production Expansion** - Grow storage without downtime  
✅ **Real-time Monitoring** - Live dashboard with color-coded usage  
✅ **Snapshot Management** - Backup and rollback capability  
✅ **Safety First** - Dry-run mode, backups, validation, error handling  

## Sizing Guidelines

| Use Case | Size | Notes |
|----------|------|-------|
| Development | 20-30GB | Light usage, test environment |
| Small Stack | 30-50GB | 1-3 services, minimal DB |
| Medium Stack | 50-100GB | 5-10 services, small DB |
| Large Stack | 100GB-500GB+ | Many services, large DB |
| Database Only | 100GB-5TB+ | Depends on data size |

**Key Rule**: Never exceed 80% capacity - ZFS performance degrades significantly. Maintain 20-30% free space.

## Common Workflows

### Check All Zvol Usage
```bash
sudo ./scripts/zvol-utilities.sh list rpool
```

### Monitor Zvols in Real-time
```bash
sudo ./scripts/zvol-utilities.sh monitor rpool 5
```

### Expand a Zvol (No Downtime!)
```bash
sudo ./scripts/zvol-utilities.sh expand 100 rpool docker_app1 100G
```

### Backup Before Major Changes
```bash
sudo ./scripts/zvol-utilities.sh snapshot rpool/docker_app1 before-update
```

### Check Container Disk Usage
```bash
sudo ./scripts/zvol-utilities.sh disk-usage 100 /var/lib/docker
```

## Configuration

Edit `examples/docker-zvols.conf` to define multiple containers:

```
# Format: <container_id> <pool> <zvol_name> <size> [notes]
100 rpool docker_api_prod 50G Production API
101 rpool docker_postgres_prod 200G PostgreSQL database
102 rpool docker_dev_stack 30G Development environment
```

Then batch setup all containers:
```bash
sudo ./scripts/manage-docker-zvols.sh -c examples/docker-zvols.conf
```

## Documentation

- **[DOCKER_ZVOL_MANAGEMENT.md](docs/DOCKER_ZVOL_MANAGEMENT.md)** - Comprehensive technical guide
  - Architecture overview
  - Detailed sizing guidelines
  - ZVol expansion walkthrough
  - Monitoring and maintenance
  - Troubleshooting

- **[QUICK_REFERENCE.sh](docs/QUICK_REFERENCE.sh)** - Quick reference for common commands
  - Copy-paste ready commands
  - Common operations
  - Troubleshooting commands
  - Production setup examples

## Safety Features

✅ **Dry-run mode** (`-d` flag) - Preview changes without applying  
✅ **Automatic backups** - Config files backed up before modification  
✅ **Input validation** - All parameters validated  
✅ **Root verification** - Scripts check for root access  
✅ **Existence checks** - Pools, containers, zvols verified  
✅ **Confirmation prompts** - User confirms destructive operations  
✅ **Error recovery** - Graceful error handling  

## Requirements

- ProxMox host with ZFS
- Root access
- Existing LXC containers
- ZFS pool with available space
- Linux tools: `zfs`, `mkfs.ext4`, `pct`, `chown`

## FAQ

**Q: Do I need a separate zvol for each container?**  
A: Yes - Provides isolation, independent backup, and performance benefits.

**Q: How should I size zvols?**  
A: 30GB minimum, 50-100GB typical for multi-service stacks. Rule: Never exceed 80% full.

**Q: Can zvols be expanded in production?**  
A: Yes - Simple 2-step process with zero downtime. Use `expand` command.

**Q: Are zvols sparse?**  
A: Yes - They only use space as data is written.

**Q: Can I snapshot and backup zvols?**  
A: Yes - Use `snapshot` and `snapshots-list` commands for management.

## Getting Help

```bash
./scripts/setup-docker-zvol.sh -h
./scripts/manage-docker-zvols.sh -h
./scripts/zvol-utilities.sh help
```

## Related Documentation

See the parent repository README for:
- Overall repository structure
- Other ProxMox script collections
- Contribution guidelines

## License

These scripts are provided as-is for ProxMox administration.

---

**Last Updated**: 2026-01-24
