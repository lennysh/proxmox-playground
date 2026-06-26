# proxmox-playground - File Index

Navigation guide for all files in the repository.

## Repository Structure

```
proxmox-playground/
├── README.md                           Main repository overview
├── CONTRIBUTING.md                     Contribution guidelines
├── .gitignore                          Git ignore patterns
├── docs/                               Root documentation
│   ├── FILE_INDEX.md                   This file
│   └── PROJECT_SUMMARY.md              Collections overview
├── docker-zvol/                        Docker ZVol collection
│   ├── README.md
│   ├── scripts/
│   │   ├── setup-docker-zvol.sh
│   │   ├── manage-docker-zvols.sh
│   │   └── zvol-utilities.sh
│   ├── examples/docker-zvols.conf
│   └── docs/
│       ├── DOCKER_ZVOL_MANAGEMENT.md
│       └── QUICK_REFERENCE.sh
├── vm-import/                          VM disk import
│   ├── README.md
│   └── scripts/import-qcow2-zfs.sh
└── backup-summary/                     vzdump log summaries
    ├── README.md
    ├── scripts/summarize-vzdump-log.sh
    └── example-logs/
```

---

## Root Level

| File | Purpose |
|------|---------|
| **README.md** | Repository overview, quick start, collection links |
| **CONTRIBUTING.md** | Guidelines for adding scripts and collections |
| **docs/FILE_INDEX.md** | This navigation guide |
| **docs/PROJECT_SUMMARY.md** | Brief overview of all collections |

---

## docker-zvol

**Location:** `docker-zvol/`  
**README:** [docker-zvol/README.md](../docker-zvol/README.md)

| File | Purpose |
|------|---------|
| `scripts/setup-docker-zvol.sh` | Create and attach a Docker zvol for one LXC container |
| `scripts/manage-docker-zvols.sh` | Batch setup from `examples/docker-zvols.conf` |
| `scripts/zvol-utilities.sh` | List, monitor, expand, snapshot zvols |
| `examples/docker-zvols.conf` | Batch config template |
| `docs/DOCKER_ZVOL_MANAGEMENT.md` | Architecture, sizing, expansion, troubleshooting |
| `docs/QUICK_REFERENCE.sh` | Copy-paste command reference |

**Quick start:**
```bash
cd docker-zvol
sudo ./scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G
```

---

## vm-import

**Location:** `vm-import/`  
**README:** [vm-import/README.md](../vm-import/README.md)

| File | Purpose |
|------|---------|
| `scripts/import-qcow2-zfs.sh` | Import qcow2/raw/vmdk into a Proxmox VM on ZFS storage |

**Quick start:**
```bash
cd vm-import
sudo ./scripts/import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2
```

---

## backup-summary

**Location:** `backup-summary/`  
**README:** [backup-summary/README.md](../backup-summary/README.md)

| File | Purpose |
|------|---------|
| `scripts/summarize-vzdump-log.sh` | Summarize vzdump task logs (failures, incomplete VMs) |
| `example-logs/` | Sample task logs for testing |

**Quick start:**
```bash
cd backup-summary
./scripts/summarize-vzdump-log.sh --errors-only /path/to/task-UPID.log
```

---

## Quick paths by goal

| Goal | Start here |
|------|------------|
| Docker storage in LXC | `docker-zvol/README.md` |
| Import a VM disk image | `vm-import/README.md` |
| Review a vzdump log | `backup-summary/README.md` |
| Add a new collection | `CONTRIBUTING.md` |
| Repo overview | `README.md` or `docs/PROJECT_SUMMARY.md` |

---

## Script inventory

| Script | Lines (approx.) | Collection |
|--------|-----------------|------------|
| `setup-docker-zvol.sh` | 453 | docker-zvol |
| `manage-docker-zvols.sh` | 312 | docker-zvol |
| `zvol-utilities.sh` | 451 | docker-zvol |
| `import-qcow2-zfs.sh` | 405 | vm-import |
| `summarize-vzdump-log.sh` | 167 | backup-summary |

---

**Last Updated**: 2026-06-26
