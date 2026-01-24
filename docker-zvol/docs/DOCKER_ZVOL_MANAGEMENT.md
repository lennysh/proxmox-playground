# ProxMox Docker ZVol Management Guide

This guide addresses best practices for managing multiple ZFS zvols for Docker in ProxMox LXC containers.

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Sizing Guidelines](#sizing-guidelines)
3. [Managing Multiple Containers](#managing-multiple-containers)
4. [ZVol Expansion](#zvol-expansion)
5. [Monitoring and Maintenance](#monitoring-and-maintenance)
6. [Troubleshooting](#troubleshooting)

## Architecture Overview

### Why Individual ZVols?
Your approach of using individual zvols per container is **the correct design** for several reasons:

- **Performance Isolation**: Each container gets dedicated storage performance
- **Failure Isolation**: A full zvol in one container won't affect others
- **Easy Backup**: Each zvol can be snapshotted and backed up independently
- **Resource Control**: You can set quotas and reservation limits per zvol
- **Flexibility**: Each container can have different storage performance tuning

### Data Flow
```
Proxmox Host (ZFS Pool: rpool)
    ↓
    ├─ zvol: docker_app1 (30GB) → LXC 100 → /var/lib/docker
    ├─ zvol: docker_app2 (50GB) → LXC 101 → /var/lib/docker
    ├─ zvol: docker_app3 (100GB) → LXC 102 → /var/lib/docker
    └─ zvol: docker_app4 (25GB) → LXC 103 → /var/lib/docker
```

## Sizing Guidelines

### What Should You Size For?

1. **Docker Images**: The total size of all images you'll pull and store
   - Base images (Ubuntu, Alpine, CentOS, etc.): 50MB - 1GB each
   - Application images: 500MB - 3GB each
   - Database images: 300MB - 2GB each

2. **Container Storage**: Runtime data, logs, and temporary files
   - Each running container: 100MB - 500MB typically
   - Database containers: Much larger (depends on data)

3. **Docker Metadata**: Layers, cache, and metadata (~5-10% of total)

4. **Headroom**: Always leave 20-30% free space
   - ZFS performance degrades significantly when > 80% full
   - Snapshots need free space
   - Allows for image updates

### Sizing Examples

| Use Case | App Type | Recommended Size | Notes |
|----------|----------|------------------|-------|
| Development | Single app | 20-30GB | Light usage, fewer images |
| Microservices Stack | 5-10 apps | 50-100GB | Multiple images, possibly databases |
| Database | PostgreSQL/MySQL | 100-500GB+ | Data growth over time |
| CI/CD Build Cache | Build system | 50-200GB | Many different build images |
| Simple HTTP Apps | Web apps | 20-50GB | Small images, quick pulls |

### Conservative Formula

```
zvol_size = (num_images × avg_image_size) + (num_containers × container_overhead) + headroom
zvol_size = (5 × 800MB) + (3 × 200MB) + 50%
zvol_size = (4GB) + (600MB) + 50% = ~7GB minimum

But realistically, allocate at least 30GB minimum even for "small" stacks
```

## Managing Multiple Containers

### Naming Convention

Use a consistent naming scheme for your zvols:

```bash
# Option 1: By application
docker_appname_v1
docker_database_postgres
docker_cache_redis

# Option 2: By stack/environment
docker_stack_prod_1
docker_stack_dev_1
docker_stack_test_1

# Option 3: By container ID
docker_lxc_100
docker_lxc_101
docker_lxc_102
```

**Recommendation**: Use `docker_<appname>_<version>` for clarity and version tracking.

### Setup Script Usage

For each container, you'll run:

```bash
# Container 100: Production API
./setup-docker-zvol.sh -c 100 -p rpool -z docker_api_prod -s 50G

# Container 101: Production Database
./setup-docker-zvol.sh -c 101 -p rpool -z docker_postgres_prod -s 200G

# Container 102: Development Stack
./setup-docker-zvol.sh -c 102 -p rpool -z docker_dev_stack -s 30G

# Container 103: CI/CD
./setup-docker-zvol.sh -c 103 -p rpool -z docker_cicd -s 100G
```

### Batch Setup Script (Optional)

Create a config file-driven setup:

```bash
# containers.conf
100 rpool docker_api_prod 50G
101 rpool docker_postgres_prod 200G
102 rpool docker_dev_stack 30G
103 rpool docker_cicd 100G
```

Then create a wrapper script to process them all at once.

## ZVol Expansion

### YES - ZVols CAN Be Expanded!

Good news: You can absolutely increase zvol size in production without downtime.

### Steps to Expand a ZVol

#### 1. Before Expansion (Check Current Usage)
```bash
# Check zvol properties
zfs list -o name,volsize,referenced rpool/docker_app1
zfs get volsize rpool/docker_app1

# Check filesystem usage inside container
# SSH into container or use:
pct exec 100 -- df -h /var/lib/docker
```

#### 2. Expand the ZVol (No Container Downtime!)
```bash
# Expand zvol from 30GB to 50GB
zfs set volsize=50G rpool/docker_app1

# Verify expansion
zfs get volsize rpool/docker_app1
```

#### 3. Expand the Filesystem Inside Container
```bash
# SSH into the container or use pct exec:
# If /var/lib/docker is ext4:
pct exec 100 -- resize2fs /dev/zvol/rpool/docker_app1

# Verify
pct exec 100 -- df -h /var/lib/docker
```

### Expansion Process Diagram

```
# BEFORE (using only 22GB of 30GB)
zfs set volsize=30G rpool/docker_app1
┌────────────────────────────────────┐
│ 30GB zvol - 22GB used - 8GB free   │
└────────────────────────────────────┘

# STEP 1: Expand zvol to 50GB
zfs set volsize=50G rpool/docker_app1
┌──────────────────────────────────────────────────────┐
│ 50GB zvol - 22GB used - 28GB free (unallocated)     │
└──────────────────────────────────────────────────────┘

# STEP 2: Expand ext4 filesystem
resize2fs /dev/zvol/rpool/docker_app1
┌──────────────────────────────────────────────────────┐
│ 50GB filesystem - 22GB used - 28GB free (available)  │
└──────────────────────────────────────────────────────┘
```

### Expansion Script

Here's a helper script to expand a zvol:

```bash
#!/bin/bash
# expand-docker-zvol.sh

set -euo pipefail

CONTAINER_ID="$1"
POOL="$2"
ZVOL_NAME="$3"
NEW_SIZE="$4"

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <container_id> <pool> <zvol_name> <new_size>"
    echo "Example: $0 100 rpool docker_app1 100G"
    exit 1
fi

ZVOL_PATH="$POOL/$ZVOL_NAME"
ZVOL_DEV="/dev/zvol/$ZVOL_PATH"

echo "[INFO] Current zvol size:"
zfs get volsize "$ZVOL_PATH"

echo "[INFO] Current usage:"
pct exec "$CONTAINER_ID" -- df -h /var/lib/docker

echo "[INFO] Expanding zvol to $NEW_SIZE..."
zfs set volsize="$NEW_SIZE" "$ZVOL_PATH"

echo "[INFO] Expanded. New size:"
zfs get volsize "$ZVOL_PATH"

echo "[INFO] Expanding filesystem inside container..."
pct exec "$CONTAINER_ID" -- resize2fs "$ZVOL_DEV"

echo "[SUCCESS] Expansion complete!"
pct exec "$CONTAINER_ID" -- df -h /var/lib/docker
```

### Expansion Best Practices

- ✅ Can be done **while container is running**
- ✅ Can be done **multiple times**
- ✅ No data loss
- ⚠️ Always check current usage first
- ⚠️ Plan expansions during maintenance windows if nervous
- ⚠️ Keep adequate headroom (never >80% full)

## Monitoring and Maintenance

### Check ZVol Health

```bash
# List all docker zvols
zfs list -o name,volsize,referenced,available rpool | grep docker

# Get detailed stats
zfs get all rpool/docker_app1 | grep -E "volsize|referenced|available|usedbydataset"

# Monitor compression ratio (if enabled)
zfs get compression,compressratio rpool/docker_app1
```

### Monitor Container Disk Usage

```bash
# View from Proxmox host
zfs list -Hr rpool/docker_app1

# From inside container
pct exec 100 -- df -h /var/lib/docker
pct exec 100 -- du -sh /var/lib/docker/*
```

### Set Up Alerts

```bash
# Example: Alert if zvol > 80% used
POOL="rpool"
THRESHOLD=80

for zvol in $(zfs list -Hr $POOL | grep docker_ | awk '{print $1}'); do
    USED=$(zfs get -H -o value used "$zvol")
    QUOTA=$(zfs get -H -o value volsize "$zvol")
    PCT=$((100 * USED / QUOTA))
    
    if [[ $PCT -gt $THRESHOLD ]]; then
        echo "WARNING: $zvol is $PCT% full"
    fi
done
```

### Snapshots and Backups

```bash
# Create snapshot before major changes
zfs snapshot rpool/docker_app1@before-update

# List snapshots
zfs list -t snapshot | grep docker_app1

# Send snapshot to backup
zfs send rpool/docker_app1@before-update | ssh backup-host "zfs recv tank/backups/docker_app1"

# Rollback if needed
zfs rollback rpool/docker_app1@before-update
```

## Troubleshooting

### Issue: Docker can't write to /var/lib/docker

**Symptoms**: Permission denied errors in Docker daemon logs

**Solution**:
```bash
# Re-run the setup script's permission fix
mkdir /tmp/zvol_tmp
mount /dev/zvol/rpool/docker_app1 /tmp/zvol_tmp
chown -R 100000:100000 /tmp/zvol_tmp
umount /tmp/zvol_tmp
```

### Issue: ZVol not appearing after creation

**Symptoms**: Device `/dev/zvol/rpool/docker_app1` doesn't exist

**Solution**:
```bash
# Rescan ZFS devices
# For Linux:
udevadm trigger

# For FreeBSD:
sysctl vfs.zfs.debug=1

# Verify zvol exists
zfs list -t volume rpool

# If still missing, check ZFS status
zfs status rpool
```

### Issue: Container won't start after adding mountpoint

**Symptoms**: Container fails to start after modifying `.conf` file

**Solution**:
```bash
# Check configuration syntax
pct config 100

# Restore from backup if syntax error
cp /etc/pve/lxc/100.conf.backup_* /etc/pve/lxc/100.conf

# Verify zvol device exists
ls -la /dev/zvol/rpool/docker_app1

# Check device permissions
stat /dev/zvol/rpool/docker_app1
```

### Issue: Performance is slow

**Possible Causes and Solutions**:

1. **Zvol too full (>80%)**
   ```bash
   zfs get available rpool/docker_app1
   # Expand with: zfs set volsize=<new_size> rpool/docker_app1
   ```

2. **No headroom for snapshots**
   ```bash
   zfs list -o name,available rpool/docker_app1
   # Delete old snapshots or expand zvol
   ```

3. **Underlying pool is slow**
   ```bash
   zpool iostat -v rpool 1 5  # Monitor I/O patterns
   ```

4. **Too many snapshots**
   ```bash
   zfs list -t snapshot | grep docker_app1 | wc -l
   # Clean up old snapshots
   ```

## Summary: Quick Reference

### Create a Docker ZVol
```bash
./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G
```

### Expand a ZVol
```bash
zfs set volsize=50G rpool/docker_app1
pct exec 100 -- resize2fs /dev/zvol/rpool/docker_app1
```

### Monitor Usage
```bash
zfs list -o name,volsize,referenced,available rpool | grep docker
```

### Each Container Needs Its Own ZVol
Yes - this is the correct design for isolation and performance.

### Can ZVols Be Expanded?
Yes - anytime, with no downtime.

### General Sizing Rule
30GB minimum for single-app stacks, 50-100GB+ for multi-app stacks with databases.
