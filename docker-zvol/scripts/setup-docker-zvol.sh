#!/bin/bash

################################################################################
# ProxMox Docker ZVol Setup Script
# 
# This script automates the creation and mounting of ZFS zvols for Docker
# storage in ProxMox LXC containers.
#
# Usage: ./setup-docker-zvol.sh -c <container_id> -p <pool> -z <zvol_name> -s <size>
#
# Example: ./setup-docker-zvol.sh -c 100 -p rpool -z docker_app1 -s 30G
#
################################################################################

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Trap to show helpful message on unexpected exit
trap 'echo -e "\n${RED}[ERROR]${NC} Script failed unexpectedly at line $LINENO. Check the error message above." >&2' ERR

# Script variables
CONTAINER_ID=""
POOL=""
ZVOL_NAME=""
ZVOL_SIZE=""
DRY_RUN=false
VERBOSE=false

################################################################################
# Functions
################################################################################

print_usage() {
    cat << EOF
Usage: $0 -c <container_id> -p <pool> -z <zvol_name> -s <size> [options]

Required arguments:
  -c, --container-id    ProxMox LXC container ID (numeric)
  -p, --pool            ZFS pool name (e.g., rpool, tank)
  -z, --zvol-name       Name for the zvol (e.g., docker_app1)
  -s, --size            Size of zvol (e.g., 30G, 100G, 1T)

Optional arguments:
  -d, --dry-run         Show what would be done without making changes
  -v, --verbose         Enable verbose output
  -h, --help            Display this help message

Examples:
  # Create 30GB zvol for container 100
  $0 -c 100 -p rpool -z docker_app1 -s 30G

  # Create 1TB zvol for container 101 with verbose output
  $0 -c 101 -p tank -z docker_app2 -s 1T -v

  # Dry-run to see what would happen
  $0 -c 102 -p rpool -z docker_app3 -s 50G -d

EOF
    exit 1
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*"
    fi
}

run_cmd() {
    local cmd="$*"
    verbose "Running: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
    else
        if ! eval "$cmd"; then
            print_error "Command failed: $cmd"
            return 1
        fi
    fi
}

################################################################################
# Validation Functions
################################################################################

validate_args() {
    if [[ -z "$CONTAINER_ID" ]] || [[ -z "$POOL" ]] || [[ -z "$ZVOL_NAME" ]] || [[ -z "$ZVOL_SIZE" ]]; then
        print_error "Missing required arguments"
        print_usage
    fi

    # Validate container ID is numeric
    if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
        print_error "Container ID must be numeric"
        exit 1
    fi

    # Validate size format
    if ! [[ "$ZVOL_SIZE" =~ ^[0-9]+([KMGT]B?)?$ ]]; then
        print_error "Invalid size format. Use format like: 30G, 100GB, 1T, etc."
        exit 1
    fi

    # Validate zvol name (alphanumeric, underscore, hyphen only)
    if ! [[ "$ZVOL_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid zvol name. Use only alphanumeric characters, underscores, and hyphens"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_prerequisites() {
    local missing_cmds=()

    for cmd in zfs mkfs.ext4 systemctl pct; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_cmds[*]}"
        print_error "This script must be run on a ProxMox host"
        exit 1
    fi
}

check_pool_exists() {
    if ! zfs list "$POOL" &>/dev/null; then
        print_error "ZFS pool '$POOL' not found"
        echo "Available pools:"
        zfs list -o name -H | grep -E '^[a-zA-Z0-9_-]+$' | head -10
        exit 1
    fi
    print_success "ZFS pool '$POOL' found"
}

check_container_exists() {
    if ! pct status "$CONTAINER_ID" &>/dev/null; then
        print_warning "Container $CONTAINER_ID not found or not accessible"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Container $CONTAINER_ID found"
    fi
}

check_zvol_exists() {
    local zvol_path="$POOL/$ZVOL_NAME"
    if zfs list "$zvol_path" &>/dev/null; then
        print_error "ZVol '$zvol_path' already exists"
        exit 1
    fi
    verbose "Confirmed zvol '$zvol_path' does not exist yet"
}

################################################################################
# Setup Functions
################################################################################

create_zvol() {
    local zvol_path="$POOL/$ZVOL_NAME"
    local zvol_dev="/dev/zvol/$zvol_path"
    
    print_info "Creating sparse zvol: $zvol_path ($ZVOL_SIZE)"
    run_cmd "zfs create -s -V $ZVOL_SIZE $zvol_path"
    
    # Wait for device to appear
    if [[ "$DRY_RUN" != true ]]; then
        local max_attempts=10
        local attempt=0
        while [[ ! -e "$zvol_dev" ]] && [[ $attempt -lt $max_attempts ]]; do
            verbose "Waiting for device $zvol_dev to appear... (attempt $((attempt + 1))/$max_attempts)"
            sleep 1
            ((attempt++))
        done
        
        if [[ ! -e "$zvol_dev" ]]; then
            print_error "Device $zvol_dev did not appear after $max_attempts seconds"
            exit 1
        fi
        print_success "Device $zvol_dev appeared"
    fi
}

verify_zvol() {
    local zvol_path="$POOL/$ZVOL_NAME"
    local zvol_dev="/dev/zvol/$zvol_path"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would verify zvol properties (volsize, referenced)"
        return 0
    fi
    
    print_info "Verifying zvol properties:"
    zfs get volsize,referenced "$zvol_path" | tail -1
}

format_zvol_ext4() {
    local zvol_dev="/dev/zvol/$POOL/$ZVOL_NAME"
    
    print_info "Formatting zvol as ext4: $zvol_dev"
    
    if [[ "$DRY_RUN" != true ]]; then
        # Check if device exists
        if [[ ! -e "$zvol_dev" ]]; then
            print_error "Device $zvol_dev does not exist"
            exit 1
        fi
        
        # Format with ext4 (disable journaling for better performance with sparse data)
        mkfs.ext4 -F -m 1 "$zvol_dev"
        print_success "Formatted $zvol_dev as ext4"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would format $zvol_dev as ext4"
    fi
}

set_permissions() {
    local zvol_dev="/dev/zvol/$POOL/$ZVOL_NAME"
    local tmp_mount="/tmp/zvol_tmp_$$"
    
    print_info "Setting correct permissions for LXC (unprivileged container: UID 100000)"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would mount $zvol_dev to $tmp_mount and set ownership to 100000:100000"
        return 0
    fi
    
    # Create temp mount point
    mkdir -p "$tmp_mount"
    
    # Mount the zvol
    verbose "Mounting $zvol_dev to $tmp_mount"
    mount "$zvol_dev" "$tmp_mount"
    
    # Set permissions for unprivileged container
    # UID/GID 100000 is typically the start of the subuid/subgid range for unprivileged containers
    verbose "Setting ownership to 100000:100000"
    chown -R 100000:100000 "$tmp_mount"
    chmod -R 755 "$tmp_mount"
    
    # Unmount
    verbose "Unmounting $tmp_mount"
    umount "$tmp_mount"
    rm -rf "$tmp_mount"
    
    print_success "Permissions set correctly"
}

add_mountpoint_to_lxc() {
    local container_conf="/etc/pve/lxc/$CONTAINER_ID.conf"
    local zvol_dev="/dev/zvol/$POOL/$ZVOL_NAME"
    
    print_info "Adding mountpoint to LXC container $CONTAINER_ID configuration"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would add mountpoint to $container_conf"
        echo -e "${YELLOW}[DRY-RUN]${NC} Mount entry: mp${NEXT_MP_INDEX}: $zvol_dev, mp=/var/lib/docker, backup=0"
        return 0
    fi
    
    # Check if config file exists
    if [[ ! -f "$container_conf" ]]; then
        print_error "Container config file not found: $container_conf"
        print_error "Make sure container $CONTAINER_ID exists"
        exit 1
    fi
    
    # Find next available mountpoint index
    local next_index=0
    while grep -q "^mp$next_index:" "$container_conf" 2>/dev/null; do
        ((next_index++))
    done
    
    # Create backup
    cp "$container_conf" "$container_conf.backup_$(date +%s)"
    print_info "Backup created: $container_conf.backup_*"
    
    # Add mountpoint entry
    local mp_entry="mp$next_index: $zvol_dev,mp=/var/lib/docker,backup=0"
    echo "$mp_entry" >> "$container_conf"
    
    verbose "Added to config: $mp_entry"
    print_success "Mountpoint added to container configuration (mp$next_index)"
}

restart_container() {
    local should_restart=false
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would suggest restarting container $CONTAINER_ID"
        return 0
    fi
    
    if pct status "$CONTAINER_ID" &>/dev/null; then
        if pct status "$CONTAINER_ID" | grep -q "running"; then
            print_warning "Container $CONTAINER_ID is currently running"
            read -p "Restart container to apply changes? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                should_restart=true
            fi
        fi
    fi
    
    if [[ "$should_restart" == true ]]; then
        print_info "Restarting container $CONTAINER_ID..."
        run_cmd "pct reboot $CONTAINER_ID"
        print_success "Container restarted"
    else
        print_info "Container will use new mountpoint after next restart"
    fi
}

################################################################################
# Main Setup Orchestration
################################################################################

run_setup() {
    print_info "=========================================="
    print_info "ProxMox Docker ZVol Setup"
    print_info "=========================================="
    print_info "Container ID: $CONTAINER_ID"
    print_info "ZFS Pool: $POOL"
    print_info "ZVol Name: $ZVOL_NAME"
    print_info "ZVol Size: $ZVOL_SIZE"
    print_info "Dry Run: $DRY_RUN"
    print_info "=========================================="
    echo
    
    check_prerequisites
    check_root
    check_pool_exists
    check_container_exists
    check_zvol_exists
    
    echo
    print_info "Step 1: Creating sparse zvol"
    create_zvol
    
    echo
    print_info "Step 2: Verifying zvol properties"
    verify_zvol
    
    echo
    print_info "Step 3: Formatting zvol as ext4"
    format_zvol_ext4
    
    echo
    print_info "Step 4: Setting permissions for unprivileged LXC"
    set_permissions
    
    echo
    print_info "Step 5: Adding mountpoint to LXC configuration"
    add_mountpoint_to_lxc
    
    echo
    print_info "Step 6: Container restart"
    restart_container
    
    echo
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "========== DRY RUN COMPLETE =========="
        print_info "Review the output above and run again without -d to execute"
    else
        print_success "========== SETUP COMPLETE =========="
        print_info "The zvol is ready for Docker use"
        print_info "Docker daemon will use: /var/lib/docker"
        print_info "Backed by zvol: $POOL/$ZVOL_NAME"
    fi
    print_info "=========================================="
}

################################################################################
# Main Entry Point
################################################################################

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--container-id)
                CONTAINER_ID="$2"
                shift 2
                ;;
            -p|--pool)
                POOL="$2"
                shift 2
                ;;
            -z|--zvol-name)
                ZVOL_NAME="$2"
                shift 2
                ;;
            -s|--size)
                ZVOL_SIZE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                ;;
        esac
    done
    
    validate_args
    run_setup
}

# Run main function
main "$@"
