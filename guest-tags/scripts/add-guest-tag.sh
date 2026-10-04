#!/bin/bash

################################################################################
# Add a Proxmox tag to a QEMU VM or LXC container without replacing existing tags.
#
# Detects guest type from cluster config (any node). Usage:
#   ./add-guest-tag.sh -v 100 -t no-backup
#
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

trap 'echo -e "\n${RED}[ERROR]${NC} Script failed unexpectedly at line $LINENO." >&2' ERR

VMIDS=()
TAGS=()
DRY_RUN=false
VERBOSE=false

print_usage() {
    cat << EOF
Usage: $0 -v <vmid>[,vmid...] -t <tag> [options]

Add one or more tags to a QEMU VM or LXC container. Existing tags are kept.
Guest type is detected from /etc/pve (cluster filesystem) on any node.

Required arguments:
  -v, --vmid           Guest ID (repeat or comma-separated)
  -t, --tag            Tag to add (repeat for several tags)

Optional arguments:
  -d, --dry-run        Show the resulting tag list; do not write
  --verbose            Verbose output
  -h, --help           This help

Examples:
  $0 -v 100 -t no-backup
  $0 -v 100 -t backup-stop -d
  $0 -v 100,101,102 -t no-backup
  $0 -v 9000 -t no-backup -t backup-stop

EOF
    exit "${1:-1}"
}

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*"
    fi
}

is_vmid() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 100 && 10#$1 <= 999999999))
}

validate_tag() {
    local tag="$1"
    if [[ -z "$tag" ]]; then
        print_error "Tag must not be empty"
        return 1
    fi
    if [[ "$tag" == *';'* || "$tag" == *','* ]]; then
        print_error "Tag must not contain ';' or ',': $tag"
        return 1
    fi
    if [[ "$tag" =~ [[:space:]] ]]; then
        print_error "Tag must not contain whitespace: $tag"
        return 1
    fi
}

append_vmids() {
    local spec="$1"
    local part
    IFS=',' read -ra parts <<< "$spec"
    for part in "${parts[@]}"; do
        part="${part// /}"
        [[ -z "$part" ]] && continue
        if ! is_vmid "$part"; then
            print_error "Invalid VMID: $part"
            exit 1
        fi
        VMIDS+=("$part")
    done
}

# Returns qemu or lxc on stdout.
detect_guest_type() {
    local vmid="$1"
    local qemu_conf="/etc/pve/qemu-server/${vmid}.conf"
    local lxc_conf="/etc/pve/lxc/${vmid}.conf"

    if [[ -f "$qemu_conf" && -f "$lxc_conf" ]]; then
        print_error "VMID $vmid has both QEMU and LXC configs"
        return 1
    fi
    if [[ -f "$qemu_conf" ]]; then
        echo qemu
        return 0
    fi
    if [[ -f "$lxc_conf" ]]; then
        echo lxc
        return 0
    fi

    if command -v pvesh >/dev/null 2>&1; then
        local gtype
        gtype="$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
            | python3 -c "
import json,sys
vmid=int(sys.argv[1])
data=json.load(sys.stdin)
for item in data:
    if int(item.get('vmid') or -1)==vmid and item.get('type') in ('qemu','lxc'):
        print(item['type'])
        break
" "$vmid" || true)"
        if [[ "$gtype" == qemu || "$gtype" == lxc ]]; then
            echo "$gtype"
            return 0
        fi
    fi

    print_error "No QEMU VM or LXC container with VMID $vmid"
    return 1
}

read_tags_line() {
    local config
    config="$1"
    echo "$config" | sed -n 's/^tags:[[:space:]]*//p' | head -n 1
}

# Prints a semicolon-separated tag list with $2 appended unless already present.
merge_tag_list() {
    local existing="$1"
    local add="$2"
    local -a out=()
    local piece trimmed found=0

    while IFS= read -r piece; do
        trimmed="${piece#"${piece%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" ]] && continue
        out+=("$trimmed")
        if [[ "$trimmed" == "$add" ]]; then
            found=1
        fi
    done < <(printf '%s\n' "$existing" | tr ';' '\n')

    if [[ "$found" -eq 0 ]]; then
        out+=("$add")
    fi

    local IFS=';'
    echo "${out[*]}"
}

add_tags_to_guest() {
    local vmid="$1"
    local gtype tool config existing new_list tag before
    gtype="$(detect_guest_type "$vmid")"
    if [[ "$gtype" == qemu ]]; then
        tool=qm
    else
        tool=pct
    fi
    if ! command -v "$tool" >/dev/null 2>&1; then
        print_error "'$tool' not found (run this on a Proxmox node)"
        return 1
    fi

    config="$("$tool" config "$vmid")"
    existing="$(read_tags_line "$config")"
    new_list="$existing"
    print_info "VMID $vmid is ${gtype} (using $tool)"
    verbose "Current tags: ${existing:-<none>}"

    for tag in "${TAGS[@]}"; do
        before="$new_list"
        new_list="$(merge_tag_list "$new_list" "$tag")"
        if [[ "$new_list" == "$before" ]]; then
            print_warning "VMID $vmid already has tag '$tag'"
        else
            print_info "VMID $vmid: will add '$tag'"
        fi
    done

    if [[ "$new_list" == "$existing" ]]; then
        print_success "VMID $vmid unchanged: ${existing:-<none>}"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $tool set $vmid --tags $new_list"
        return 0
    fi

    verbose "Running: $tool set $vmid --tags $new_list"
    "$tool" set "$vmid" --tags "$new_list"
    print_success "VMID $vmid tags: $new_list"
}

################################################################################
# Parse args
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--vmid)
            [[ $# -ge 2 ]] || print_usage
            append_vmids "$2"
            shift 2
            ;;
        -t|--tag)
            [[ $# -ge 2 ]] || print_usage
            validate_tag "$2" || exit 1
            TAGS+=("$2")
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            print_usage 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            ;;
    esac
done

if [[ ${#VMIDS[@]} -eq 0 || ${#TAGS[@]} -eq 0 ]]; then
    print_error "Both -v/--vmid and -t/--tag are required"
    print_usage
fi

if [[ "$DRY_RUN" != true && $EUID -ne 0 ]]; then
    print_error "Must run as root to change guest config (or use -d)"
    exit 1
fi

if [[ ! -d /etc/pve && ! "$(command -v pvesh || true)" ]]; then
    print_error "This does not look like a Proxmox node (/etc/pve missing, no pvesh)"
    exit 1
fi

failed=0
for vmid in "${VMIDS[@]}"; do
    if ! add_tags_to_guest "$vmid"; then
        failed=1
    fi
done

exit "$failed"
