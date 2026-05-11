#!/usr/bin/env bash
# Create a new Proxmox LXC from an OCI registry image using the same mechanism as
# the Proxmox VE UI: pull the image into CT template storage (vztmpl) via the
# storage API oci-registry-pull (skopeo docker:// → oci-archive in the vztmpl
# directory), then pct create with STORAGE:vztmpl/<normalized>.tar.
#
# Requires PVE with POST /nodes/{node}/storage/{storage}/oci-registry-pull (PVE 9.x
# with OCI template support). Run on a cluster node as root.
#
# Reference format matches the UI/API: e.g. docker.io/library/nginx:latest,
# ghcr.io/org/image:tag. A leading oci:// or docker:// prefix is stripped before pull.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: oci-ct-create-from-registry.sh [options]

Required:
  --storage ID          Storage where templates live (must allow content vztmpl)
  --reference REF       OCI image reference for the API (e.g. docker.io/library/nginx:latest)
  --rootfs SPEC         New CT root disk: STORAGE:GiB_integer (e.g. local-zfs:8)

Common options:
  --vmid ID             CT VMID (default: cluster next free id via pvesh /cluster/nextid)
  --hostname NAME       pct --hostname (default: oci-ct-<vmid>)
  --net0 SPEC           pct --net0 (default: name=eth0,bridge=vmbr0,ip=dhcp)
  --node NAME           PVE node name (default: pvecm nodename, else hostname -s)
  --memory MB           pct --memory
  --cores N             pct --cores
  --ostype TYPE         pct --ostype (e.g. debian, alpine)
  --unprivileged 0|1    pct --unprivileged (default: 1)
  --features SPEC       pct --features
  --onboot 0|1          pct --onboot (default: 0)

Additional volumes (mount points inside the CT; new disks on STORAGE):
  --mp SPEC             Repeatable. SPEC = STORAGE:GiB:/path  (e.g. --mp local-zfs:32:/var/lib/data)
                        → pct --mp0 STORAGE:GiB,mp=/path  (mp1, mp2, … in order)

Pull behaviour:
  --skip-pull           Do not call oci-registry-pull; use an already-downloaded template
  --reuse-local-template If normalized .tar already exists under vztmpl, skip pull

Other:
  --pull-only           Only download the template to storage, then exit (no pct create)
  -h, --help            This help

Example:
  ./oci-ct-create-from-registry.sh \\
    --storage local \\
    --reference docker.io/library/nginx:latest \\
    --rootfs local-zfs:8 \\
    --hostname nginx-oci-1 \\
    --mp local-zfs:10:/var/cache/nginx

After create, start with: pct start <vmid>
EOF
  exit 1
}

die() { echo "$*" >&2; exit 1; }

STORAGE=""
REFERENCE=""
ROOTFS_SPEC=""
VMID=""
HOSTNAME=""
NET0="${OCI_CT_CREATE_NET0:-name=eth0,bridge=vmbr0,ip=dhcp}"
NODE=""
MEMORY=""
CORES=""
OSTYPE=""
UNPRIV="1"
FEATURES=""
ONBOOT="0"
SKIP_PULL=0
REUSE_LOCAL=0
PULL_ONLY=0
MP_SPECS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage)            STORAGE="${2:?}"; shift 2 ;;
    --reference)         REFERENCE="${2:?}"; shift 2 ;;
    --rootfs)           ROOTFS_SPEC="${2:?}"; shift 2 ;;
    --vmid)             VMID="${2:?}"; shift 2 ;;
    --hostname)         HOSTNAME="${2:?}"; shift 2 ;;
    --net0)             NET0="${2:?}"; shift 2 ;;
    --node)             NODE="${2:?}"; shift 2 ;;
    --memory)           MEMORY="${2:?}"; shift 2 ;;
    --cores)            CORES="${2:?}"; shift 2 ;;
    --ostype)           OSTYPE="${2:?}"; shift 2 ;;
    --unprivileged)     UNPRIV="${2:?}"; shift 2 ;;
    --features)         FEATURES="${2:?}"; shift 2 ;;
    --onboot)           ONBOOT="${2:?}"; shift 2 ;;
    --mp)               MP_SPECS+=("${2:?}"); shift 2 ;;
    --skip-pull)        SKIP_PULL=1; shift ;;
    --reuse-local-template) REUSE_LOCAL=1; shift ;;
    --pull-only)        PULL_ONLY=1; shift ;;
    -h|--help)          usage ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

[[ -n "$STORAGE" ]] || die "Missing --storage"
[[ -n "$REFERENCE" ]] || die "Missing --reference"
if [[ "$PULL_ONLY" -eq 1 ]]; then
  :
elif [[ -n "$ROOTFS_SPEC" ]]; then
  :
else
  die "Missing --rootfs (required unless --pull-only)"
fi

command -v jq >/dev/null 2>&1 || die "jq is required (for pvesh JSON and task status)."
command -v pvesh >/dev/null 2>&1 || die "pvesh not found (run on a Proxmox VE node as root)."
if [[ "$PULL_ONLY" -eq 0 ]]; then
  command -v pct >/dev/null 2>&1 || die "pct not found (run on a Proxmox VE node as root)."
fi

node_name() {
  if command -v pvecm &>/dev/null; then
    local n
    n="$(pvecm nodename 2>/dev/null)" || true
    [[ -n "$n" ]] && { printf '%s\n' "$n"; return; }
  fi
  hostname -s
}

[[ -n "$NODE" ]] || NODE="$(node_name)"

# Match PVE::Storage::normalize_content_filename (pve-storage) used by oci-registry-pull.
normalize_content_filename() {
  perl -MPVE::Storage -e '
    print PVE::Storage::normalize_content_filename($ARGV[0]) . "\n";
  ' "$1"
}

strip_oci_scheme() {
  local r="$1"
  case "$r" in
    oci://*) r="${r#oci://}" ;;
    docker://*) r="${r#docker://}" ;;
  esac
  printf '%s\n' "$r"
}

REFERENCE="$(strip_oci_scheme "$REFERENCE")"

vztmpl_dir_for_storage() {
  local sid="$1"
  perl -MPVE::Storage -e 'print PVE::Storage::get_vztmpl_dir(PVE::Storage::config(), $ARGV[0]) . "\n"' "$sid" \
    || die "Could not resolve vztmpl directory for storage '$sid' (perl PVE::Storage failed — run on a PVE node?)"
}

# pvesh JSON varies by version: {"data": N}, {"data": "N"}, double-encoded string, or bare number.
next_cluster_id() {
  local out id
  out=$(pvesh get /cluster/nextid --output-format json 2>/dev/null) || return 1
  [[ -n "$out" ]] || return 1

  if command -v jq >/dev/null 2>&1; then
    id=$(printf '%s\n' "$out" | jq -r '
      def unwrap:
        if type == "string" then
          if test("^\\s*\\{") then fromjson else . end
        else . end;
      unwrap
      | if type == "object" and (.data != null) then .data else . end
      | if type == "number" then tostring
        elif type == "string" and test("^[0-9]+$") then .
        else empty end
    ')
  else
    id=$(printf '%s\n' "$out" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p')
    [[ -n "$id" ]] || id=$(printf '%s\n' "$out" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    [[ -n "$id" ]] || id=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p')
  fi

  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

wait_for_task() {
  local upid="$1" max="${2:-7200}" waited=0
  local status exitstatus line

  while [[ "$waited" -lt "$max" ]]; do
    line=$(pvesh get "/nodes/${NODE}/tasks/${upid}/status" --output-format json 2>/dev/null) || true
    if [[ -n "$line" ]]; then
      status=$(printf '%s\n' "$line" | jq -r '.data.status // empty' 2>/dev/null || true)
      if [[ "$status" == "stopped" ]]; then
        exitstatus=$(printf '%s\n' "$line" | jq -r '.data.exitstatus // empty' 2>/dev/null || true)
        if [[ "$exitstatus" == "OK" ]]; then
          return 0
        fi
        die "Task finished with exitstatus=${exitstatus:-unknown}. UPID=${upid}"
      fi
    fi
    sleep 2
    waited=$((waited + 2))
  done
  die "Timed out waiting for task ${upid} (${max}s)"
}

oci_registry_pull() {
  local ref="$1" out upid
  echo "--- oci-registry-pull (same API as Proxmox UI) ---"
  echo "Node:     ${NODE}"
  echo "Storage:  ${STORAGE}"
  echo "Reference: ${ref}"
  echo

  out=$(pvesh create "/nodes/${NODE}/storage/${STORAGE}/oci-registry-pull" \
    --reference "$ref" --output-format json 2>&1) || {
    echo "$out" >&2
    die "pvesh oci-registry-pull failed. Is this PVE version new enough, storage '${STORAGE}' enabled for vztmpl, and skopeo installed?"
  }

  upid=$(printf '%s\n' "$out" | jq -r '
    def unwrap: if type == "string" and test("^\\s*\\{") then fromjson else . end;
    unwrap | if type == "object" and (.data != null) then .data else . end
    | if type == "string" then . elif type == "number" then tostring else empty end
  ')
  [[ -n "$upid" && "$upid" != "null" ]] || die "Could not parse UPID from pvesh output: $out"

  echo "Worker UPID: ${upid}"
  echo "Waiting for pull to finish..."
  wait_for_task "$upid"
  echo "Pull completed OK."
  echo
}

NORM="$(normalize_content_filename "$REFERENCE")"
OSTEMPLATE="${STORAGE}:vztmpl/${NORM}.tar"
VZTDIR="$(vztmpl_dir_for_storage "$STORAGE")"
LOCAL_TAR="${VZTDIR}/${NORM}.tar"

if [[ "$SKIP_PULL" -eq 1 ]]; then
  echo "Skipping pull (--skip-pull). Using ostemplate: ${OSTEMPLATE}"
elif [[ "$REUSE_LOCAL" -eq 1 && -f "$LOCAL_TAR" ]]; then
  echo "Reusing existing template file: ${LOCAL_TAR}"
else
  oci_registry_pull "$REFERENCE"
fi

if [[ ! -f "$LOCAL_TAR" ]]; then
  die "Template tarball not found after pull: ${LOCAL_TAR} (expected volid ${OSTEMPLATE})"
fi

echo "Template on disk: ${LOCAL_TAR}"
ls -lh "$LOCAL_TAR" 2>/dev/null || stat "$LOCAL_TAR" 2>/dev/null || true
echo

if [[ "$PULL_ONLY" -eq 1 ]]; then
  echo "Pull-only mode: done."
  exit 0
fi

[[ -n "$VMID" ]] || VMID="$(next_cluster_id)" || die "Could not get next cluster VMID (install jq or pass --vmid)"

if pct config "$VMID" &>/dev/null; then
  die "VMID ${VMID} already exists"
fi

[[ -n "$HOSTNAME" ]] || HOSTNAME="oci-ct-${VMID}"

echo "--- pct create (from downloaded vztmpl template) ---"
echo "VMID:       ${VMID}"
echo "Ostemplate: ${OSTEMPLATE}"
echo "Rootfs:     ${ROOTFS_SPEC}"
echo "Hostname:   ${HOSTNAME}"
if [[ "${#MP_SPECS[@]}" -gt 0 ]]; then
  echo "Extra mp:   ${MP_SPECS[*]}"
fi
echo

cmd=(pct create "$VMID" "$OSTEMPLATE" --rootfs "$ROOTFS_SPEC" --hostname "$HOSTNAME" --net0 "$NET0" --unprivileged "$UNPRIV" --onboot "$ONBOOT")

[[ -n "$MEMORY" ]] && cmd+=(--memory "$MEMORY")
[[ -n "$CORES" ]] && cmd+=(--cores "$CORES")
[[ -n "$OSTYPE" ]] && cmd+=(--ostype "$OSTYPE")
[[ -n "$FEATURES" ]] && cmd+=(--features "$FEATURES")

mp_idx=0
for mp_spec in "${MP_SPECS[@]}"; do
  if [[ ! "$mp_spec" =~ ^([^:]+):([0-9]+):(/.*)$ ]]; then
    die "Invalid --mp '${mp_spec}' (expected STORAGE:GiB:/path — absolute path inside CT, size in GiB integer, same form as --rootfs storage:size)"
  fi
  mp_st="${BASH_REMATCH[1]}"
  mp_sz="${BASH_REMATCH[2]}"
  mp_path="${BASH_REMATCH[3]}"
  [[ "$mp_sz" -ge 1 ]] || die "Invalid --mp '${mp_spec}': size must be a positive integer (GiB)"
  cmd+=( "--mp${mp_idx}" "${mp_st}:${mp_sz},mp=${mp_path}" )
  mp_idx=$((mp_idx + 1))
done
unset mp_st mp_sz mp_path mp_spec 2>/dev/null || true

echo "Running:"
printf ' '; printf '%q ' "${cmd[@]}"; echo; echo
"${cmd[@]}" || die "pct create failed"

echo
echo "pct create OK. Start with: pct start ${VMID}"
