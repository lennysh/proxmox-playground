#!/bin/bash

################################################################################
# ProxMox Docker ZVol Utilities
#
# Useful utility commands for managing and monitoring Docker zvols
#
# Usage: ./zvol-utilities.sh <command> [arguments]
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[✓]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
print_error() { echo -e "${RED}[✗]${NC} $*" >&2; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

################################################################################
# Command: list
################################################################################

cmd_list() {
    local pool="${1:-rpool}"
    
    print_info "Docker zvols in pool: $pool"
    echo
    
    zfs list -Hr "$pool" 2>/dev/null | grep docker_ | \
    awk -v OFS="\t" '{
        printf "%-30s %8s %12s %12s\n", 
        $1, $2, $3, $4
    }' | column -t -s$'\t'
    
    # Add header
    echo
    echo "Usage for each zvol:"
    zfs list -Hr "$pool" 2>/dev/null | grep docker_ | \
    while read -r name used avail ref; do
        pct_used=$(( 100 * used / (used + avail) ))
        printf "  %-30s: %3d%% full\n" "$name" "$pct_used"
    done
}

################################################################################
# Command: status
################################################################################

cmd_status() {
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 status <zvol_path>"
        print_error "Example: $0 status rpool/docker_app1"
        exit 1
    fi
    
    local zvol_path="$1"
    
    if ! zfs list "$zvol_path" &>/dev/null; then
        print_error "ZVol not found: $zvol_path"
        exit 1
    fi
    
    print_info "Status for: $zvol_path"
    echo
    
    # Get properties
    local volsize=$(zfs get -H -o value volsize "$zvol_path")
    local used=$(zfs get -H -o value used "$zvol_path")
    local available=$(zfs get -H -o value available "$zvol_path")
    local referenced=$(zfs get -H -o value referenced "$zvol_path")
    
    # Calculate percentages
    local total=$((used + available))
    local pct_used=$(( 100 * used / total ))
    
    echo "Volume Size:      $volsize"
    echo "Total Used:       $(numfmt --to=iec-i --suffix=B $used 2>/dev/null || echo "$used bytes")"
    echo "Available:        $(numfmt --to=iec-i --suffix=B $available 2>/dev/null || echo "$available bytes")"
    echo "Referenced:       $(numfmt --to=iec-i --suffix=B $referenced 2>/dev/null || echo "$referenced bytes")"
    echo "Utilization:      $pct_used%"
    echo
    
    if [[ $pct_used -gt 80 ]]; then
        print_warning "ZVol is more than 80% full!"
    elif [[ $pct_used -gt 60 ]]; then
        print_warning "ZVol is more than 60% full"
    else
        print_success "ZVol has adequate space"
    fi
}

################################################################################
# Command: expand
################################################################################

cmd_expand() {
    if [[ $# -lt 3 ]]; then
        print_error "Usage: $0 expand <container_id> <pool> <zvol_name> <new_size>"
        print_error "Example: $0 expand 100 rpool docker_app1 100G"
        exit 1
    fi
    
    local container_id="$1"
    local pool="$2"
    local zvol_name="$3"
    local new_size="$4"
    
    local zvol_path="$pool/$zvol_name"
    local zvol_dev="/dev/zvol/$zvol_path"
    
    check_root
    
    if ! zfs list "$zvol_path" &>/dev/null; then
        print_error "ZVol not found: $zvol_path"
        exit 1
    fi
    
    print_info "Expanding zvol: $zvol_path"
    echo
    
    # Show current status
    print_info "Current status:"
    cmd_status "$zvol_path"
    
    echo
    read -p "Expand to $new_size? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        exit 0
    fi
    
    # Expand zvol
    print_info "Expanding zvol volume..."
    zfs set volsize="$new_size" "$zvol_path"
    print_success "ZVol volume expanded"
    
    # Expand filesystem inside container
    print_info "Expanding filesystem inside container..."
    if pct status "$container_id" &>/dev/null; then
        if pct exec "$container_id" -- resize2fs "$zvol_dev"; then
            print_success "Filesystem expanded successfully"
        else
            print_error "Failed to expand filesystem"
            print_warning "You may need to manually run: resize2fs $zvol_dev"
            exit 1
        fi
    else
        print_warning "Container $container_id not found or not accessible"
        print_info "You may need to manually expand the filesystem"
        print_info "Command: resize2fs $zvol_dev"
        exit 1
    fi
    
    # Show new status
    echo
    print_info "New status:"
    cmd_status "$zvol_path"
}

################################################################################
# Command: monitor
################################################################################

cmd_monitor() {
    local pool="${1:-rpool}"
    local interval="${2:-5}"
    
    check_root
    
    print_info "Monitoring docker zvols (updating every ${interval}s, press Ctrl+C to stop)"
    echo
    
    while true; do
        clear
        echo -e "${BLUE}ProxMox Docker ZVol Monitor${NC} - $(date)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        
        zfs list -Hr "$pool" 2>/dev/null | grep docker_ | while read -r name used avail ref; do
            if [[ -z "$name" ]]; then
                continue
            fi
            
            # Calculate percentages
            local total=$((used + avail))
            local pct_used=$(( 100 * used / total ))
            
            # Create progress bar
            local bar_length=30
            local filled=$(( pct_used * bar_length / 100 ))
            local empty=$(( bar_length - filled ))
            
            local bar="["
            for ((i = 0; i < filled; i++)); do
                if [[ $pct_used -gt 80 ]]; then
                    bar+="${RED}█${NC}"
                elif [[ $pct_used -gt 60 ]]; then
                    bar+="${YELLOW}█${NC}"
                else
                    bar+="${GREEN}█${NC}"
                fi
            done
            for ((i = 0; i < empty; i++)); do
                bar+=" "
            done
            bar+="]"
            
            printf "%-30s %s %3d%%\n" "${name##*/}" "$bar" "$pct_used"
        done
        
        echo
        sleep "$interval"
    done
}

################################################################################
# Command: snapshot
################################################################################

cmd_snapshot() {
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 snapshot <zvol_path> [snapshot_name]"
        print_error "Example: $0 snapshot rpool/docker_app1 before-update"
        exit 1
    fi
    
    local zvol_path="$1"
    local snapshot_name="${2:-backup-$(date +%Y%m%d-%H%M%S)}"
    
    check_root
    
    if ! zfs list "$zvol_path" &>/dev/null; then
        print_error "ZVol not found: $zvol_path"
        exit 1
    fi
    
    local snapshot_fullname="$zvol_path@$snapshot_name"
    
    print_info "Creating snapshot: $snapshot_fullname"
    
    if zfs snapshot "$snapshot_fullname"; then
        print_success "Snapshot created: $snapshot_fullname"
        
        # Show snapshots for this zvol
        echo
        print_info "Existing snapshots:"
        zfs list -t snapshot | grep "$zvol_path@"
    else
        print_error "Failed to create snapshot"
        exit 1
    fi
}

################################################################################
# Command: snapshots-list
################################################################################

cmd_snapshots_list() {
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 snapshots-list <zvol_path>"
        print_error "Example: $0 snapshots-list rpool/docker_app1"
        exit 1
    fi
    
    local zvol_path="$1"
    
    if ! zfs list "$zvol_path" &>/dev/null; then
        print_error "ZVol not found: $zvol_path"
        exit 1
    fi
    
    print_info "Snapshots for: $zvol_path"
    echo
    
    zfs list -t snapshot -H | grep "^$zvol_path@" | \
    awk '{printf "  %-30s %12s\n", $1, $3}' | column -t
}

################################################################################
# Command: rollback
################################################################################

cmd_rollback() {
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 rollback <snapshot_fullname>"
        print_error "Example: $0 rollback rpool/docker_app1@before-update"
        exit 1
    fi
    
    local snapshot="$1"
    
    check_root
    
    print_warning "Rolling back to snapshot: $snapshot"
    print_warning "This will destroy all data since this snapshot!"
    echo
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_warning "Cancelled"
        exit 0
    fi
    
    print_info "Rolling back..."
    if zfs rollback -r "$snapshot"; then
        print_success "Rolled back to: $snapshot"
    else
        print_error "Rollback failed"
        exit 1
    fi
}

################################################################################
# Command: disk-usage
################################################################################

cmd_disk_usage() {
    if [[ $# -lt 2 ]]; then
        print_error "Usage: $0 disk-usage <container_id> <zvol_mount>"
        print_error "Example: $0 disk-usage 100 /var/lib/docker"
        exit 1
    fi
    
    local container_id="$1"
    local mount_path="$2"
    
    print_info "Disk usage on container $container_id at $mount_path:"
    echo
    
    pct exec "$container_id" -- du -sh "$mount_path"/* 2>/dev/null | sort -rh || \
        print_error "Could not get disk usage"
}

################################################################################
# Help
################################################################################

print_help() {
    cat << EOF
ProxMox Docker ZVol Utilities

Usage: $0 <command> [arguments]

Available Commands:

  list [pool]                      List all docker zvols in pool
  status <zvol_path>               Show detailed status of a zvol
  expand <cid> <pool> <zvol> <sz>  Expand a zvol to new size
  monitor [pool] [interval]        Monitor zvols in real-time
  snapshot <zvol_path> [name]      Create snapshot of zvol
  snapshots-list <zvol_path>       List all snapshots of zvol
  rollback <snapshot>              Rollback to a snapshot
  disk-usage <cid> <mount_path>    Show disk usage in container
  help                             Show this help

Examples:

  List all docker zvols:
    $0 list rpool

  Check status of a zvol:
    $0 status rpool/docker_app1

  Expand a zvol from 30GB to 50GB:
    $0 expand 100 rpool docker_app1 50G

  Monitor zvols in real-time:
    $0 monitor rpool 5

  Create a backup snapshot:
    $0 snapshot rpool/docker_app1 backup-2024-01-20

  List snapshots:
    $0 snapshots-list rpool/docker_app1

  Check disk usage inside container:
    $0 disk-usage 100 /var/lib/docker

EOF
}

################################################################################
# Main
################################################################################

main() {
    if [[ $# -lt 1 ]]; then
        print_help
        exit 1
    fi
    
    case "$1" in
        list)
            shift
            cmd_list "$@"
            ;;
        status)
            shift
            cmd_status "$@"
            ;;
        expand)
            shift
            cmd_expand "$@"
            ;;
        monitor)
            shift
            cmd_monitor "$@"
            ;;
        snapshot)
            shift
            cmd_snapshot "$@"
            ;;
        snapshots-list)
            shift
            cmd_snapshots_list "$@"
            ;;
        rollback)
            shift
            cmd_rollback "$@"
            ;;
        disk-usage)
            shift
            cmd_disk_usage "$@"
            ;;
        help|-h|--help)
            print_help
            ;;
        *)
            print_error "Unknown command: $1"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
