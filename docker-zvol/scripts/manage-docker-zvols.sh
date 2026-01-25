#!/bin/bash

################################################################################
# ProxMox Docker ZVol Batch Manager
#
# Manage multiple Docker zvols from a configuration file
#
# Usage: ./manage-docker-zvols.sh -c <config_file> [-v] [-d]
#
# Config file format (one entry per line):
# <container_id> <pool> <zvol_name> <size> [<optional_notes>]
#
# Example:
# 100 rpool docker_api_prod 50G Production API service
# 101 rpool docker_postgres_prod 200G PostgreSQL database
# 102 rpool docker_dev_stack 30G Development environment
#
################################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Script variables
CONFIG_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-docker-zvol.sh"
VERBOSE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

print_header() {
    echo -e "${PURPLE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}  $1"
    echo -e "${PURPLE}╚════════════════════════════════════════════╝${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

print_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*"
    fi
}

print_usage() {
    cat << EOF
Usage: $0 -c <config_file> [options]

Required:
  -c, --config          Config file with zvol definitions

Optional:
  -v, --verbose         Verbose output
  -d, --dry-run         Show what would be done
  -y, --yes             Skip confirmation prompts
  -h, --help            Show this help

Config File Format:
  <container_id> <pool> <zvol_name> <size> [notes]

Example Config:
  100 rpool docker_api_prod 50G API service
  101 rpool docker_postgres 200G Database
  102 rpool docker_redis 10G Cache layer

EOF
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
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
    
    if [[ -z "$CONFIG_FILE" ]]; then
        print_error "Config file required"
        print_usage
    fi
}

check_prerequisites() {
    verbose "Checking prerequisites..."
    
    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        print_error "Setup script not found: $SETUP_SCRIPT"
        print_error "Make sure setup-docker-zvol.sh exists in the same directory"
        exit 1
    fi
    
    if [[ ! -x "$SETUP_SCRIPT" ]]; then
        verbose "Making setup script executable"
        chmod +x "$SETUP_SCRIPT"
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

parse_config() {
    verbose "Parsing config file: $CONFIG_FILE"
    
    local line_num=0
    local entries_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse line
        read -r container_id pool zvol_name size notes <<< "$line"
        
        # Validate required fields
        if [[ -z "$container_id" || -z "$pool" || -z "$zvol_name" || -z "$size" ]]; then
            print_warning "Skipping invalid line $line_num: missing fields"
            continue
        fi
        
        # Store entry
        ENTRIES[$entries_count]="$container_id|$pool|$zvol_name|$size|$notes"
        ((entries_count++))
        
    done < "$CONFIG_FILE"
    
    if [[ $entries_count -eq 0 ]]; then
        print_error "No valid entries found in config file"
        exit 1
    fi
    
    echo $entries_count
}

display_plan() {
    local total_entries=$1
    
    print_header "Execution Plan"
    echo
    
    printf "%-5s %-12s %-15s %-20s %-15s %-25s\n" \
        "Num" "Container" "Pool" "ZVol Name" "Size" "Notes"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    for ((i = 0; i < total_entries; i++)); do
        IFS='|' read -r container_id pool zvol_name size notes <<< "${ENTRIES[$i]}"
        printf "%-5d %-12s %-15s %-20s %-15s %-25s\n" \
            $((i + 1)) "$container_id" "$pool" "$zvol_name" "$size" "${notes:-N/A}"
    done
    
    echo
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
}

run_entry_setup() {
    local entry_num=$1
    local container_id=$2
    local pool=$3
    local zvol_name=$4
    local size=$5
    
    print_header "Setting up Entry $entry_num: $zvol_name"
    echo
    
    local cmd="$SETUP_SCRIPT -c $container_id -p $pool -z $zvol_name -s $size"
    
    if [[ "$DRY_RUN" == true ]]; then
        cmd="$cmd -d"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        cmd="$cmd -v"
    fi
    
    if "$cmd"; then
        print_success "Entry $entry_num completed successfully"
        return 0
    else
        print_error "Entry $entry_num failed with status $?"
        return 1
    fi
}

process_entries() {
    local total_entries=$1
    local failed_count=0
    local success_count=0
    
    print_header "Processing Entries"
    echo
    
    for ((i = 0; i < total_entries; i++)); do
        IFS='|' read -r container_id pool zvol_name size notes <<< "${ENTRIES[$i]}"
        
        if run_entry_setup $((i + 1)) "$container_id" "$pool" "$zvol_name" "$size"; then
            ((success_count++))
        else
            ((failed_count++))
            if [[ "$SKIP_CONFIRMATION" != true ]]; then
                read -p "Continue with remaining entries? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_warning "Stopped by user"
                    break
                fi
            fi
        fi
        echo
    done
    
    print_header "Summary"
    echo
    echo "Total entries: $total_entries"
    echo -e "${GREEN}✓ Successful: $success_count${NC}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}✗ Failed: $failed_count${NC}"
    fi
    echo
}

main() {
    parse_args "$@"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE"
    fi
    
    print_header "ProxMox Docker ZVol Batch Manager"
    
    check_prerequisites
    echo
    
    # Parse config and get count
    declare -a ENTRIES
    total_entries=$(parse_config)
    print_success "Loaded $total_entries entries from config"
    echo
    
    # Display execution plan
    display_plan "$total_entries"
    
    # Ask for confirmation unless -y flag
    if [[ "$SKIP_CONFIRMATION" != true ]] && [[ "$DRY_RUN" != true ]]; then
        read -p "Proceed with setup? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Aborted by user"
            exit 0
        fi
    fi
    
    # Process all entries
    process_entries "$total_entries"
}

main "$@"
