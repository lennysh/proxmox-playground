#!/usr/bin/env bash
# Refresh an OCI-based (or any) LXC rootfs on Proxmox VE by syncing a new
# image into the existing CT's root volume. Bind mounts (mpX) in the old CT
# config are unchanged; only the rootfs tree is replaced.
#
# Run on the Proxmox node as root. The CT must be local to this node.
set -euo pipefail

usage() {
  echo "Usage: $0 [options] <old_ctid> <new_oci_ref> [temp_ctid]"
  echo ""
  echo "Options:"
  echo "  --no-snapshot             Skip pct snapshot entirely"
  echo "  --allow-failed-snapshot   Try pct snapshot, but continue if it fails (default: abort on failure)"
  echo "  -h, --help                Show this help"
  echo ""
  echo "  old_ctid     Running or stopped CT to update (keeps same CTID, net, mpX, ...)"
  echo "  new_oci_ref  New image, e.g. oci://docker.io/library/nginx:latest"
  echo "  temp_ctid    Optional; default: next free cluster VMID"
  echo ""
  echo "Example:"
  echo "  $0 100 oci://docker.io/library/nginx:latest"
  echo "  $0 --allow-failed-snapshot 100 oci://docker.io/library/nginx:latest"
  echo "  $0 --no-snapshot 100 oci://docker.io/library/nginx:latest"
  exit 1
}

SKIP_SNAPSHOT=0
ALLOW_FAILED_SNAPSHOT=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    --no-snapshot)             SKIP_SNAPSHOT=1; shift ;;
    --allow-failed-snapshot)   ALLOW_FAILED_SNAPSHOT=1; shift ;;
    -h|--help)                 usage ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

[[ ${1:-} ]] && [[ ${2:-} ]] || usage
if [[ "$SKIP_SNAPSHOT" -ne 0 && "$ALLOW_FAILED_SNAPSHOT" -ne 0 ]]; then
  echo "Cannot combine --no-snapshot with --allow-failed-snapshot (nothing to allow)." >&2
  exit 1
fi

OLD="$1"
NEW_OCI="$2"

next_cluster_id() {
  if command -v jq >/dev/null 2>&1; then
    pvesh get /cluster/nextid --output-format json | jq -r '.data // empty'
  else
    pvesh get /cluster/nextid --output-format json | sed -n 's/.*"data" *: *\([0-9][0-9]*\).*/\1/p'
  fi
}

if [[ -n "${3:-}" ]]; then
  TEMP="$3"
else
  TEMP="$(next_cluster_id)"
fi

if [[ "$TEMP" == "$OLD" ]]; then
  echo "temp_ctid equals old_ctid; pass an explicit temp id." >&2
  exit 1
fi

if ! pct config "$OLD" &>/dev/null; then
  echo "No CT config for vmid $OLD (wrong id or not on this node?)." >&2
  exit 1
fi

# First field of value line: "key: value" (value may contain ':')
cfg() {
  pct config "$1" | sed -n "s/^$2: //p" | head -1
}

ROOTFS_LINE="$(cfg "$OLD" rootfs)"
if [[ -z "$ROOTFS_LINE" ]]; then
  echo "Could not read rootfs: for CT $OLD" >&2
  exit 1
fi

# rootfs: pool:volume,size=8G  -> storage id is substring before first comma's first ':'... 
# Actually format is: STORAGE:VOLREF,size=8G  e.g. local-zfs:vm-100-disk-0,size=32G
# Storage id is everything before the first ':' that starts the volume part - tricky.
# Proxmox storage is first segment before ':' only for simple case local-zfs:subvol
STORAGE="${ROOTFS_LINE%%:*}"
VOL_AND_REST="${ROOTFS_LINE#*:}"
SIZE="${VOL_AND_REST##*,size=}"
SIZE="${SIZE%%,*}"

if [[ -z "$SIZE" || "$SIZE" == "$VOL_AND_REST" ]]; then
  echo "Could not parse size= from rootfs line: $ROOTFS_LINE" >&2
  exit 1
fi

HOST="$(cfg "$OLD" hostname)"
OSTYPE="$(cfg "$OLD" ostype)"
UNPRIV="$(cfg "$OLD" unprivileged)"
ARCH="$(cfg "$OLD" arch)"
FEATURES="$(cfg "$OLD" features)"

M_OLD="/var/lib/lxc/${OLD}/rootfs"
M_NEW="/var/lib/lxc/${TEMP}/rootfs"

echo "Old CT:     $OLD"
echo "Temp CT:    $TEMP"
echo "New image:  $NEW_OCI"
echo "Rootfs ref: $ROOTFS_LINE (using storage ${STORAGE}, size ${SIZE})"
echo ""

pct stop "$OLD"

# Proxmox integrates pct snapshot with snapshot-capable rootfs/mp storages (e.g. ZFS).
# Bind-mount host paths are not part of the root volume; snapshot mainly covers managed volumes.
if [[ "$SKIP_SNAPSHOT" -eq 0 ]]; then
  SNAP_NAME="pre-oci-refresh-$(date -u +%Y%m%d-%H%M%S)UTC"
  SNAP_DESC="oci-ct-refresh-rootfs.sh before rsync from ${NEW_OCI}"
  echo "Creating snapshot '${SNAP_NAME}' on CT ${OLD}..."
  set +e
  pct snapshot "$OLD" "$SNAP_NAME" --description "$SNAP_DESC"
  snap_rc=$?
  set -e
  if [[ "$snap_rc" -eq 0 ]]; then
    echo "Snapshot OK. Rollback example: pct rollback ${OLD} ${SNAP_NAME}"
  else
    if [[ "$ALLOW_FAILED_SNAPSHOT" -eq 0 ]]; then
      echo "Snapshot failed (exit ${snap_rc}); aborting. Fix storage/snapshot support or pass --allow-failed-snapshot." >&2
      exit 1
    fi
    echo "Warning: pct snapshot failed (exit ${snap_rc}); continuing (--allow-failed-snapshot)." >&2
    echo "         For rollback safety use snapshot-capable storage, or vzdump/PBS for backups." >&2
  fi
  echo ""
else
  echo "Skipping snapshot (--no-snapshot)."
  echo ""
fi

if pct config "$TEMP" &>/dev/null; then
  echo "Temp CT $TEMP already exists; reusing (will stop and refresh from image)." >&2
else
  create_args=(
    pct create "$TEMP" "$NEW_OCI"
    --hostname "${HOST:-oci-refresh-temp}"
    --rootfs "${STORAGE}:${SIZE}"
    --onboot 0
  )
  [[ -n "$OSTYPE" ]] && create_args+=( --ostype "$OSTYPE" )
  [[ -n "$UNPRIV" ]] && create_args+=( --unprivileged "$UNPRIV" )
  [[ -n "$ARCH" ]] && create_args+=( --arch "$ARCH" )
  [[ -n "$FEATURES" ]] && create_args+=( --features "$FEATURES" )
  # Minimal valid net; replace with copying net0 from $OLD if you use static IP for create.
  create_args+=( --net0 name=eth0,bridge=vmbr0,ip=dhcp )
  "${create_args[@]}"
fi

pct stop "$TEMP"

cleanup_mounts() {
  pct unmount "$TEMP" 2>/dev/null || true
  pct unmount "$OLD" 2>/dev/null || true
}
trap cleanup_mounts EXIT

pct mount "$OLD"
pct mount "$TEMP"

if [[ ! -d "$M_OLD" || ! -d "$M_NEW" ]]; then
  echo "Expected mount paths missing after pct mount:" >&2
  echo "  $M_OLD" >&2
  echo "  $M_NEW" >&2
  exit 1
fi

excludes=()
while IFS= read -r line; do
  [[ "$line" == *mp=* ]] || continue
  if [[ "$line" =~ mp=([^,]+) ]]; then
    cpath="${BASH_REMATCH[1]}"
    [[ "$cpath" == /* ]] || cpath="/$cpath"
    excludes+=( --exclude="${cpath#/}" )
  fi
done < <(pct config "$OLD" | grep -E '^mp[0-9]+:' || true)

echo "Syncing new root -> old root (rsync)..."
rsync -aHAX --delete "${excludes[@]}" "${M_NEW}/" "${M_OLD}/"

trap - EXIT
pct unmount "$TEMP"
pct unmount "$OLD"

pct destroy "$TEMP"
pct start "$OLD"

echo ""
echo "Done: CT $OLD root refreshed from $NEW_OCI (mpX / config unchanged)."
