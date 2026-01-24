# lennysh-proxmox-scripts - File Index

## 📁 Repository Structure

```
lennysh-proxmox-scripts/
├── README.md                           Main repository overview
├── CONTRIBUTING.md                     Contribution guidelines
├── .gitignore                          Git ignore patterns
├── docs/                               Root documentation
│   ├── FILE_INDEX.md                   This file
│   └── PROJECT_SUMMARY.md              Project overview
└── docker-zvol/                        Docker ZVol Collection
    ├── README.md                       Collection overview
    ├── scripts/                        Executable scripts
    │   ├── setup-docker-zvol.sh        Single container setup
    │   ├── manage-docker-zvols.sh      Batch setup
    │   └── zvol-utilities.sh           Monitor & maintain
    ├── examples/                       Configuration templates
    │   └── docker-zvols.conf           Example config
    └── docs/                           Collection documentation
        ├── DOCKER_ZVOL_MANAGEMENT.md   Technical guide
        └── QUICK_REFERENCE.sh          Command reference
```

## 📄 Root Level Files

### **README.md**
- **Purpose**: Main repository overview and navigation
- **For**: First-time visitors, repository overview
- **Contains**: Structure, quick start, collections list, roadmap

### **CONTRIBUTING.md**
- **Purpose**: Guidelines for contributing new scripts and collections
- **For**: Contributors, maintainers
- **Contains**: Structure guidelines, coding standards, documentation requirements

### **.gitignore**
- **Purpose**: Git ignore patterns for ProxMox-specific files
- **For**: Preventing sensitive files from being committed
- **Contains**: Backup patterns, config backups, temporary files

---

## 📚 Documentation Files

### **docs/FILE_INDEX.md** (This File)
- **Purpose**: Navigation guide for all files in the repository
- **For**: Understanding the file organization
- **Location**: `/docs/FILE_INDEX.md`

### **docs/PROJECT_SUMMARY.md**
- **Purpose**: Overall project information and quick reference
- **For**: Quick overview, answers to common questions
- **Location**: `/docs/PROJECT_SUMMARY.md`

---

## 🐳 Docker-ZVol Collection

### Collection Overview

**Location**: `docker-zvol/`  
**Purpose**: Docker storage management in ProxMox LXC containers using ZFS zvols  
**Status**: ✅ Complete and production-ready

### 🚀 Executable Scripts

**1. scripts/setup-docker-zvol.sh** (447 lines)
   - **Purpose**: Setup single LXC container with Docker zvol
   - **Usage**: `sudo docker-zvol/scripts/setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G`
   - **Key Features**:
     - Create sparse zvol
     - Format ext4 with correct permissions
     - Add to container config
     - Backup config before modification
     - Dry-run mode, verbose output

**2. scripts/manage-docker-zvols.sh** (312 lines)
   - **Purpose**: Batch setup multiple containers from config file
   - **Usage**: `sudo docker-zvol/scripts/manage-docker-zvols.sh -c docker-zvol/examples/docker-zvols.conf`
   - **Key Features**:
     - Config file driven
     - Preview execution plan
     - Progress tracking
     - Skip confirmation mode
     - Summary reporting

**3. scripts/zvol-utilities.sh** (451 lines)
   - **Purpose**: Monitor, maintain, and manage zvols
   - **Usage**: `sudo docker-zvol/scripts/zvol-utilities.sh <command> [args]`
   - **Available Commands**:
     - `list [pool]` - List all docker zvols
     - `status <zvol>` - Detailed zvol information
     - `expand <cid> <pool> <zvol> <size>` - Expand zvol (no downtime!)
     - `monitor [pool] [interval]` - Real-time monitoring
     - `snapshot <zvol> [name]` - Create snapshot
     - `snapshots-list <zvol>` - List snapshots
     - `rollback <snapshot>` - Rollback to snapshot
     - `disk-usage <cid> <mount>` - Check container disk usage



### 📚 Documentation Files

**4. docs/README.md** (350+ lines)
   - **Purpose**: Collection overview and quick start
   - **For**: Collection users, quick start guide
   - **Contains**: Overview, quick start, script references, sizing guidelines, FAQ

**5. docs/DOCKER_ZVOL_MANAGEMENT.md** (409 lines)
   - **Purpose**: Technical deep dive and detailed guide
   - **For**: Technical users, architects, production planning
   - **Contains**: Architecture, sizing formulas, expansion guide, monitoring, troubleshooting

**6. docs/QUICK_REFERENCE.sh** (243 lines)
   - **Purpose**: Copy-paste ready commands and examples
   - **For**: Users who want quick command reference
   - **Contains**: Common commands, troubleshooting, production examples, sizing cheat sheet

### ⚙️ Configuration & Examples

**7. examples/docker-zvols.conf** (29 lines)
   - **Purpose**: Template for batch setup configuration
   - **Usage**: Edit this, then run `manage-docker-zvols.sh`
   - **Format**: `<container_id> <pool> <zvol_name> <size> [notes]`
   - **Example entries**: Production API, database, cache, CI/CD, dev environment

---

## 🎯 Quick Reference by Purpose

### "I want to get started quickly"
1. Read: `docker-zvol/README.md` (Quick Start section)
2. Run: `docker-zvol/scripts/setup-docker-zvol.sh -h`
3. Execute: Single container setup

### "I'm setting up multiple containers"
1. Read: `docker-zvol/README.md` (Configuration section)
2. Edit: `docker-zvol/examples/docker-zvols.conf`
3. Execute: `docker-zvol/scripts/manage-docker-zvols.sh`

### "I want to understand the architecture"
1. Read: `docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md` (Architecture section)
2. Read: `docker-zvol/README.md` (Overview)
3. Review: `docs/PROJECT_SUMMARY.md` (Architecture diagram)

### "I want to learn best practices"
1. Read: `docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md`
2. Review: `docker-zvol/docs/QUICK_REFERENCE.sh` (examples)
3. Check: `docker-zvol/README.md` (Safety Features)

### "I want to monitor and maintain zvols"
1. Use: `docker-zvol/scripts/zvol-utilities.sh`
2. Reference: `docker-zvol/docs/QUICK_REFERENCE.sh` (monitoring commands)
3. Read: `docker-zvol/docs/DOCKER_ZVOL_MANAGEMENT.md` (Monitoring section)

### "I want to contribute new scripts"
1. Read: `CONTRIBUTING.md` (guidelines and standards)
2. Review: `docker-zvol/README.md` (structure)
3. Follow: Script guidelines in CONTRIBUTING.md

---

## 🎯 Quick Start Paths

### Path 1: Single Container (5 minutes)
```
1. Read: README.md (Quick Start section)
2. Run:  ./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G -d
3. Run:  ./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G
4. Done: Container ready for Docker!
```

### Path 2: Multiple Containers (10 minutes)
```
1. Read: README.md (Common Workflows section)
2. Edit: docker-zvols.conf (your containers)
3. Run:  ./manage-docker-zvols.sh -c docker-zvols.conf -d
4. Run:  ./manage-docker-zvols.sh -c docker-zvols.conf
5. Done: All containers ready!
```

### Path 3: Understanding the Design (20 minutes)
```
1. Read: PROJECT_SUMMARY.md (Architecture section)
2. Read: DOCKER_ZVOL_MANAGEMENT.md (first 3 sections)
3. Read: README.md (Common Workflows)
4. You understand the "why" and "how"
```

### Path 4: Maintenance Mode (Ongoing)
```
1. Bookmark: QUICK_REFERENCE.sh (common commands)
2. Use:  ./zvol-utilities.sh monitor rpool 5 (watch usage)
3. When: Expand with ./zvol-utilities.sh expand <args>
4. Monitor regularly, expand proactively
```

---

## 📊 Document Purposes at a Glance

| Document | Purpose | Read Time | Audience |
|----------|---------|-----------|----------|
| README.md | Complete guide, everything you need | 10-15 min | Everyone |
| DOCKER_ZVOL_MANAGEMENT.md | Technical deep dive, architecture | 15-20 min | Architects, advanced users |
| PROJECT_SUMMARY.md | What was created, answers to questions | 5-10 min | Quick reference, overview |
| QUICK_REFERENCE.sh | Copy-paste ready commands | 2-5 min | Copy and paste users |
| docker-zvols.conf | Your container definitions | Edit time | Batch setup users |

---

## ⭐ Direct Answers to Your Questions

**Q: Do I need a separate zvol for each container?**
→ See: PROJECT_SUMMARY.md (Question 1 section)
→ Answer: YES - Isolation, backup, performance benefits

**Q: How should I size the zvols?**
→ See: DOCKER_ZVOL_MANAGEMENT.md (Sizing Guidelines section)
→ See: PROJECT_SUMMARY.md (Question 2 section)
→ Answer: 30GB+ min, 50-100GB typical, +50% headroom

**Q: Can zvols be expanded after production use?**
→ See: DOCKER_ZVOL_MANAGEMENT.md (ZVol Expansion section)
→ See: PROJECT_SUMMARY.md (Question 3 section)
→ Answer: YES - Simple 2-step process, no downtime

---

## 🔐 Safety & Best Practices

✅ **Always use `-d` flag first**
```bash
./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G -d
```

✅ **Backups are automatic**
- Config files backed up before modification
- Named: `/etc/pve/lxc/100.conf.backup_<timestamp>`

✅ **Test before production**
- Use dry-run on non-production container first
- Verify: `sudo pct exec 100 -- docker info`

✅ **Monitor regularly**
- Keep <80% full (ZFS performs best at 50-70%)
- Use: `sudo ./zvol-utilities.sh monitor rpool 5`

✅ **Expand proactively**
- Don't wait until full
- Can be done anytime, no downtime

---

## 📞 Getting Help

**For basic usage:**
```bash
./setup-docker-zvol.sh -h
./manage-docker-zvols.sh -h
./zvol-utilities.sh help
```

**For documentation:**
1. README.md - Start here
2. DOCKER_ZVOL_MANAGEMENT.md - Deep dive
3. PROJECT_SUMMARY.md - Quick reference
4. QUICK_REFERENCE.sh - Commands

**For troubleshooting:**
- README.md has "Troubleshooting" section
- DOCKER_ZVOL_MANAGEMENT.md has detailed troubleshooting

---

## 📈 Next Steps

1. **[ ] Review README.md** - Get familiar with approach
2. **[ ] Edit docker-zvols.conf** - Plan your containers
3. **[ ] Run setup on one test container** - Build confidence
4. **[ ] Monitor for a week** - Watch usage patterns
5. **[ ] Batch setup remaining containers** - Go to production
6. **[ ] Add monitoring to cron** - Automate checks
7. **[ ] Document your setup** - Keep notes for team

---

## 📂 File Statistics

- **Total Lines of Code/Docs**: ~2,700 lines
- **Scripts**: 3 executable files (~1,200 lines)
- **Documentation**: 4 markdown/reference files (~1,200 lines)
- **Configuration**: 1 editable template (~30 lines)

**All files are production-ready and fully commented.**

---

**Last Updated**: 2026-01-24
**Status**: ✅ Complete and ready to use!
