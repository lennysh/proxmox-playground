#!/usr/bin/env bash
# ProxMox Docker ZVol - Quick Reference
# Paste these commands directly into your terminal

################################################################################
# QUICK START - Single Container
################################################################################

# Dry-run first (preview what will happen)
sudo ./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G -d

# Execute the setup
sudo ./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G

# Verify it worked
sudo zfs list -o name,volsize,referenced rpool/docker_app1
sudo pct exec 100 -- df -h /var/lib/docker

################################################################################
# QUICK START - Multiple Containers
################################################################################

# Edit the config file with your containers
nano docker-zvols.conf

# Preview all setups
sudo ./manage-docker-zvols.sh -c docker-zvols.conf -d

# Execute batch setup
sudo ./manage-docker-zvols.sh -c docker-zvols.conf

################################################################################
# MONITORING & STATUS
################################################################################

# List all docker zvols with usage
sudo ./zvol-utilities.sh list rpool

# Check specific zvol status
sudo ./zvol-utilities.sh status rpool/docker_app1

# Real-time monitoring (live dashboard)
sudo ./zvol-utilities.sh monitor rpool 5

# Check disk usage inside container
sudo ./zvol-utilities.sh disk-usage 100 /var/lib/docker

################################################################################
# EXPANSION (NO DOWNTIME!)
################################################################################

# Option 1: Using utility script (recommended)
sudo ./zvol-utilities.sh expand 100 rpool docker_app1 100G

# Option 2: Manual steps
sudo zfs set volsize=100G rpool/docker_app1
sudo pct exec 100 -- resize2fs /dev/zvol/rpool/docker_app1

# Verify expansion worked
sudo ./zvol-utilities.sh status rpool/docker_app1

################################################################################
# SNAPSHOTS & BACKUPS
################################################################################

# Create snapshot before major changes
sudo ./zvol-utilities.sh snapshot rpool/docker_app1 before-update

# List all snapshots
sudo ./zvol-utilities.sh snapshots-list rpool/docker_app1

# Rollback to snapshot (⚠️ destructive - use carefully!)
sudo ./zvol-utilities.sh rollback rpool/docker_app1@before-update

################################################################################
# TROUBLESHOOTING
################################################################################

# Permission issues in container
ZVOL_DEV="/dev/zvol/rpool/docker_app1"
mkdir /tmp/zvol_tmp
sudo mount $ZVOL_DEV /tmp/zvol_tmp
sudo chown -R 100000:100000 /tmp/zvol_tmp
sudo umount /tmp/zvol_tmp

# Device not found
sudo udevadm trigger

# Check if zvol exists
sudo zfs list -t volume rpool | grep docker_

# Container config syntax check
sudo pct config 100

# Restore config from backup
sudo cp /etc/pve/lxc/100.conf.backup_* /etc/pve/lxc/100.conf

# View container logs
sudo pct logs 100

# SSH into container
sudo pct enter 100

################################################################################
# USEFUL ZFS COMMANDS (Reference)
################################################################################

# List all pools
sudo zfs list -H -o name | grep -v '/'

# List all docker zvols
sudo zfs list -o name,volsize,referenced,available rpool | grep docker_

# Get detailed zvol info
sudo zfs get all rpool/docker_app1

# Set a quota (optional - limits max size)
sudo zfs set quota=50G rpool/docker_app1

# Set a reservation (guarantees minimum available space)
sudo zfs set reservation=30G rpool/docker_app1

# Enable compression (saves space)
sudo zfs set compression=lz4 rpool/docker_app1

# Check pool health
sudo zpool status rpool

# View pool I/O stats
sudo zpool iostat -v rpool 1 5

################################################################################
# SIZING CHEAT SHEET
################################################################################

# Minimal (dev/test only)
# Size: 20-30GB
# Use case: Single small app, lots of free space
# Example: ./setup-docker-zvol.sh -c 100 -p rpool -z docker_dev -s 30G

# Small (1-3 services)
# Size: 30-50GB
# Use case: Single-service stack or small multi-service
# Example: ./setup-docker-zvol.sh -c 101 -p rpool -z docker_app -s 50G

# Medium (5-10 services with small DB)
# Size: 50-100GB
# Use case: Multi-service stack, small PostgreSQL/MySQL
# Example: ./setup-docker-zvol.sh -c 102 -p rpool -z docker_stack -s 100G

# Large (many services, large DB)
# Size: 100GB-500GB+
# Use case: Complex stacks with significant databases
# Example: ./setup-docker-zvol.sh -c 103 -p rpool -z docker_db -s 300G

################################################################################
# KEY POINTS TO REMEMBER
################################################################################

# ✅ Each container needs its own zvol (isolation, backup, performance)
# ✅ Can be expanded anytime without downtime
# ✅ Always test with -d (dry-run) flag first
# ✅ Keep 20-30% free space (don't exceed 80% full)
# ✅ Create snapshots before major changes
# ✅ Use configuration file for multiple containers
# ✅ Monitor usage regularly with 'list' or 'monitor' commands

################################################################################
# EXAMPLE PRODUCTION SETUP
################################################################################

# Create config file
cat > docker-zvols.conf << 'EOF'
# Production Setup
100 rpool docker_api_prod 50G API Microservice
101 rpool docker_postgres_prod 200G PostgreSQL Database
102 rpool docker_redis_prod 10G Redis Cache
103 rpool docker_elasticsearch_prod 150G Elasticsearch
104 rpool docker_dev_stack 30G Development/Testing
105 rpool docker_cicd 100G CI/CD Build Pipeline
EOF

# Dry-run first
sudo ./manage-docker-zvols.sh -c docker-zvols.conf -d

# Execute batch setup
sudo ./manage-docker-zvols.sh -c docker-zvols.conf -y

# After setup, verify all containers
for cid in 100 101 102 103 104 105; do
    echo "Container $cid:"
    sudo pct exec $cid -- df -h /var/lib/docker
done

################################################################################
# MONITORING SCRIPT (Run periodically)
################################################################################

# Save this as a cron job or run manually
cat > /usr/local/bin/check-docker-zvols << 'EOF'
#!/bin/bash
echo "=== Docker ZVol Status ==="
date
echo

# Check usage
/path/to/zvol-utilities.sh list rpool

# Alert if any zvol > 80% full
echo
echo "=== Alerts ==="
zfs list -Hr rpool 2>/dev/null | grep docker_ | while read name used avail ref; do
    total=$((used + avail))
    pct=$((100 * used / total))
    if [[ $pct -gt 80 ]]; then
        echo "⚠️  WARNING: ${name##*/} is $pct% full"
    fi
done
EOF

chmod +x /usr/local/bin/check-docker-zvols

# Run it
/usr/local/bin/check-docker-zvols

################################################################################
# GETTING HELP
################################################################################

# Show help for main script
./setup-docker-zvol.sh -h

# Show help for batch script
./manage-docker-zvols.sh -h

# Show help for utilities
./zvol-utilities.sh help

# Read detailed documentation
cat README.md
cat DOCKER_ZVOL_MANAGEMENT.md

################################################################################
