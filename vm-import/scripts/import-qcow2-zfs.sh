#!/bin/bash

################################################################################
# ProxMox QCOW2 to ZFS Import Script
#
# Imports a qcow2 disk image into a Proxmox VM using ZFS storage.
# Uses 'qm importdisk' which creates a ZFS zvol and converts the image.
#
# Usage: ./import-qcow2-zfs.sh -v <vmid> -i <qcow2_file> [-s <storage>] [options]
#
# Example: ./import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2 -s local-zfs
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
VMID=""
QCOW2_FILE=""
STORAGE=""
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRM=false
FORMAT="qcow2"
DISK_BUS="scsi"
SET_BOOT=false

################################################################################
# Functions
################################################################################

print_usage() {
    cat << EOF
Usage: $0 -v <vmid> -i <qcow2_file> [options]

Import a qcow2 disk image into a Proxmox VM on ZFS storage.

Required arguments:
  -v, --vmid           Proxmox VM ID (numeric)
  -i, --image          Path to the qcow2 disk image file

Optional arguments:
  -s, --storage        ZFS storage name (default: local-zfs)
                       Use 'pvesm status' to list available storage
  -f, --format         Source image format: qcow2, raw, vmdk (default: qcow2)
  -b, --bus            Disk bus: scsi, sata, virtio (default: scsi)
  --boot               Set imported disk as boot device
  -d, --dry-run        Show what would be done without making changes
  -y, --yes            Skip confirmation prompts
  --verbose            Enable verbose output
  -h, --help           Display this help message

Examples:
  # Import to existing VM 100 using default storage
  $0 -v 100 -i /root/downloads/ubuntu-server.qcow2

  # Import to VM 101 with specific ZFS storage
  $0 -v 101 -i /mnt/backup/disk.qcow2 -s local-zfs

  # Import and set as boot disk
  $0 -v 102 -i ./debian.qcow2 --boot

  # Dry-run to see what would happen
  $0 -v 100 -i /path/to/disk.qcow2 -d

  # List available storage
  pvesm status

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
    if [[ -z "$VMID" ]] || [[ -z "$QCOW2_FILE" ]]; then
        print_error "Missing required arguments"
        print_usage
    fi

    # Validate VM ID is numeric
    if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
        print_error "VM ID must be numeric"
        exit 1
    fi

    # Validate format
    if ! [[ "$FORMAT" =~ ^(qcow2|raw|vmdk)$ ]]; then
        print_error "Format must be qcow2, raw, or vmdk"
        exit 1
    fi

    # Validate bus
    if ! [[ "$DISK_BUS" =~ ^(scsi|sata|virtio)$ ]]; then
        print_error "Bus must be scsi, sata, or virtio"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (or via sudo)"
        exit 1
    fi
}

check_prerequisites() {
    local missing_cmds=()

    for cmd in qm pvesm qemu-img; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_cmds[*]}"
        print_error "This script must be run on a Proxmox host"
        exit 1
    fi
}

check_qcow2_file() {
    if [[ ! -f "$QCOW2_FILE" ]]; then
        print_error "QCOW2 file not found: $QCOW2_FILE"
        exit 1
    fi

    if [[ ! -r "$QCOW2_FILE" ]]; then
        print_error "QCOW2 file is not readable: $QCOW2_FILE"
        exit 1
    fi

    # Verify it's a valid qcow2/disk image
    if ! qemu-img info "$QCOW2_FILE" &>/dev/null; then
        print_error "File does not appear to be a valid disk image: $QCOW2_FILE"
        exit 1
    fi

    local img_size
    img_size=$(qemu-img info -f "$FORMAT" "$QCOW2_FILE" 2>/dev/null | grep "virtual size" | awk -F'[()]' '{print $2}' || echo "unknown")
    print_info "Source image: $QCOW2_FILE (${img_size:-unknown size})"
}

check_storage() {
    # pvesm status outputs: Name Type Status Total Used Available
    if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$STORAGE"; then
        print_error "Storage '$STORAGE' not found or not accessible"
        echo ""
        print_info "Available storage:"
        pvesm status 2>/dev/null | head -20
        exit 1
    fi

    local storage_info
    storage_info=$(pvesm status 2>/dev/null | awk -v s="$STORAGE" '$1==s {print; exit}')
    verbose "Storage '$STORAGE': $storage_info"

    print_success "Storage '$STORAGE' is available"
}

check_vm_exists() {
    if ! qm status "$VMID" &>/dev/null; then
        print_warning "VM $VMID does not exist"
        if [[ "$SKIP_CONFIRM" != true ]]; then
            read -p "Create new VM $VMID? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        create_vm
    else
        print_success "VM $VMID exists"
    fi
}

create_vm() {
    print_info "Creating new VM $VMID..."
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would run: qm create $VMID --name imported-vm-$VMID --memory 512 --cores 1"
    else
        qm create "$VMID" --name "imported-vm-$VMID" --memory 512 --cores 1
        print_success "VM $VMID created (minimal config - customize as needed)"
    fi
}

check_vm_stopped() {
    local status
    status=$(qm status "$VMID" 2>/dev/null | awk '{print $2}') || status=""

    if [[ "$status" == "running" ]]; then
        print_warning "VM $VMID is currently running"
        if [[ "$SKIP_CONFIRM" != true ]]; then
            read -p "Stop VM $VMID before import? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                run_cmd "qm stop $VMID"
                print_info "Waiting for VM to stop..."
                sleep 3
            else
                print_error "Import should be done with VM stopped to avoid data corruption"
                exit 1
            fi
        else
            run_cmd "qm stop $VMID"
            sleep 3
        fi
    fi
}

################################################################################
# Import Functions
################################################################################

get_next_disk_slot() {
    local vm_config
    vm_config=$(qm config "$VMID" 2>/dev/null || echo "")

    case "$DISK_BUS" in
        scsi)
            for i in {0..30}; do
                if ! echo "$vm_config" | grep -q "^${DISK_BUS}${i}:"; then
                    echo "${DISK_BUS}${i}"
                    return
                fi
            done
            ;;
        sata)
            for i in {0..5}; do
                if ! echo "$vm_config" | grep -q "^${DISK_BUS}${i}:"; then
                    echo "${DISK_BUS}${i}"
                    return
                fi
            done
            ;;
        virtio)
            for i in {0..15}; do
                if ! echo "$vm_config" | grep -q "^${DISK_BUS}${i}:"; then
                    echo "${DISK_BUS}${i}"
                    return
                fi
            done
            ;;
    esac
    echo ""
}

do_import() {
    # Get next available disk slot (qm importdisk can assign via --disk)
    local disk_id
    disk_id=$(get_next_disk_slot)

    if [[ -z "$disk_id" ]]; then
        print_error "No free disk slot found for bus $DISK_BUS"
        exit 1
    fi

    print_info "Importing $QCOW2_FILE to VM $VMID on storage $STORAGE (as $disk_id)..."
    print_info "This may take several minutes depending on image size..."

    # qm importdisk creates ZFS zvol and adds disk to VM config
    # --disk ensures we control the slot assignment
    run_cmd "qm importdisk $VMID '$QCOW2_FILE' $STORAGE --format $FORMAT --disk $disk_id"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry-run complete. Run without -d to perform actual import."
        return 0
    fi

    if [[ "$SET_BOOT" == true ]]; then
        print_info "Setting $disk_id as boot device..."
        run_cmd "qm set $VMID --boot order=$disk_id"
        print_success "Boot order updated"
    fi
}

################################################################################
# Main
################################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--vmid)
            VMID="$2"
            shift 2
            ;;
        -i|--image)
            QCOW2_FILE="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -b|--bus)
            DISK_BUS="$2"
            shift 2
            ;;
        --boot)
            SET_BOOT=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        --verbose)
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

# Default storage if not specified
[[ -z "$STORAGE" ]] && STORAGE="local-zfs"

# Run validation and import
check_root
check_prerequisites
validate_args
check_qcow2_file
check_storage
check_vm_exists
check_vm_stopped

if [[ "$SKIP_CONFIRM" != true ]] && [[ "$DRY_RUN" != true ]]; then
    echo ""
    print_info "About to import:"
    echo "  VM ID:      $VMID"
    echo "  Source:     $QCOW2_FILE"
    echo "  Storage:    $STORAGE"
    echo "  Format:     $FORMAT"
    echo ""
    read -p "Proceed with import? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Import cancelled"
        exit 0
    fi
fi

do_import

echo ""
print_success "Import complete!"
print_info "You can start the VM with: qm start $VMID"
print_info "View VM config: qm config $VMID"
