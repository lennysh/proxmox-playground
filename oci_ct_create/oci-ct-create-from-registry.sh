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

Required (omit when using --list-template-storages):
  --storage ID          Optional. Same as the UI: Datacenter → Storage id where **vztmpl**
                        (Container templates) lives — **dir** / **nfs** / **cifs**, not zfspool.
                        If omitted: **auto-picks** when exactly one candidate exists on this node;
                        otherwise **lists** candidates and exits 2. If set but invalid, same list + exit 2.
                        Explicit list only:  --list-template-storages
  --reference REF       OCI image reference for the API (e.g. docker.io/library/nginx:latest)
  --rootfs SPEC         New CT root disk: STORAGE:GiB_integer (e.g. Storage:8) — often your zfspool

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
  --mp SPEC             Repeatable. SPEC = STORAGE:SIZE:/path  (e.g. --mp local-zfs:32:/var/lib/data)
                        SIZE = GiB as integer or decimal (e.g. 8, 0.25) passed through to pct
                        → pct --mp0 STORAGE:SIZE,mp=/path  (mp1, mp2, … in order)

Pull behaviour:
  --skip-pull           Do not call oci-registry-pull; use an already-downloaded template
  --reuse-local-template If normalized .tar already exists under vztmpl, skip pull

Other:
  --list-template-storages  Print storages on this node that include vztmpl (Container templates)
                        and which ones accept oci-registry-pull (same rule as the UI). Exits 0.
                        Optional: --node N  (any order with this flag).
  --pull-only           Only download the template to storage, then exit (no pct create)
  -h, --help            This help

Example (templates on mounted storage id nfs-proxmox, CT disks on zfspool Storage):
  ./oci-ct-create-from-registry.sh \\
    --storage nfs-proxmox \\
    --reference docker.io/library/nginx:latest \\
    --rootfs Storage:8 \\
    --hostname nginx-oci-1 \\
    --mp Storage:0.25:/var/cache/nginx

After create, start with: pct start <vmid>
EOF
  exit 1
}

die() { echo "$*" >&2; exit 1; }

node_name() {
  if command -v pvecm &>/dev/null; then
    local n
    n="$(pvecm nodename 2>/dev/null)" || true
    [[ -n "$n" ]] && { printf '%s\n' "$n"; return; }
  fi
  hostname -s
}

list_template_storages() {
  local json
  if [[ -n "${STORAGE_JSON_CACHED:-}" ]]; then
    json="$STORAGE_JSON_CACHED"
  else
    json=$(pvesh get "/nodes/${NODE}/storage" --output-format json 2>/dev/null) || die "pvesh get /nodes/${NODE}/storage failed"
  fi
  if ! printf '%s\n' "$json" | jq -e . >/dev/null 2>&1; then
    echo "Storage list response was not valid JSON (first 400 chars):" >&2
    printf '%s\n' "$json" | head -c 400 >&2
    echo >&2
    die "Cannot parse /nodes/${NODE}/storage output."
  fi
  cat <<EOF
Storages on node '${NODE}' whose **content** includes **vztmpl** (Container template — same as Datacenter → Storage in the UI):

  Use the **storage id** printed below as --storage. That is the same id the UI uses when it stores
  an OCI image under your Container templates path.  oci-registry-pull **yes** means Proxmox can
  write the .tar there (dir / nfs / cifs — same API as the UI).  **no** means pick another id (e.g. your zfspool cannot host OCI pulls).

EOF
  printf '%s\n' "$json" | jq -r '
    def unwrap: if type == "string" and test("^\\s*\\{") then fromjson else . end;
    def pve_array:
      if type == "array" then .
      elif type == "object" and (.data != null) then
        (.data | if type == "array" then . else [.] end)
      else [] end;
    def has_vztmpl: (.content // "") | test("vztmpl");
    unwrap | pve_array
    | map(select(has_vztmpl))
    | sort_by(.storage // .storeid // .id)
    | .[]
    | (.storage // .storeid // .id) as $id
    | (.type // "?") as $t
    | (
        if (.path // "") != "" then .path
        elif ((.server // .address // "") | length) > 0 then
          "nfs " + (.server // .address) + " " + (.export // .exportpath // "")
        else "—"
        end
      ) as $hint
    | (if ($t == "dir" or $t == "nfs" or $t == "cifs") then "yes" else "no" end) as $ok
    | "storage id: \($id)\n  type: \($t)\n  path / export: \($hint)\n  oci-registry-pull (same rule as UI): \($ok)\n"
  '
}

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
LIST_TEMPLATE_STORAGES=0
STORAGE_JSON_CACHED=""
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
    --list-template-storages) LIST_TEMPLATE_STORAGES=1; shift ;;
    -h|--help)          usage ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

if [[ "$LIST_TEMPLATE_STORAGES" -eq 1 ]]; then
  command -v jq >/dev/null 2>&1 || die "jq is required for --list-template-storages."
  command -v pvesh >/dev/null 2>&1 || die "pvesh not found (run on a Proxmox VE node as root)."
  [[ -n "$NODE" ]] || NODE="$(node_name)"
  list_template_storages
  exit 0
fi

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

[[ -n "$NODE" ]] || NODE="$(node_name)"

load_node_storage_json() {
  STORAGE_JSON_CACHED=$(pvesh get "/nodes/${NODE}/storage" --output-format json 2>/dev/null) \
    || die "pvesh get /nodes/${NODE}/storage failed"
  if ! printf '%s\n' "$STORAGE_JSON_CACHED" | jq -e . >/dev/null 2>&1; then
    echo "Storage list was not valid JSON (first 400 chars):" >&2
    printf '%s\n' "$STORAGE_JSON_CACHED" | head -c 400 >&2
    echo >&2
    die "Cannot parse /nodes/${NODE}/storage output."
  fi
}

# True if this node has a storage entry $1 with vztmpl and a type Proxmox allows for oci-registry-pull.
template_storage_valid_for_oci_pull() {
  local sid="$1" json="$STORAGE_JSON_CACHED" n
  [[ -n "$sid" ]] || return 1
  n=$(printf '%s\n' "$json" | jq -r --arg s "$sid" '
    def unwrap: if type == "string" and test("^\\s*\\{") then fromjson else . end;
    def pve_array:
      if type == "array" then .
      elif type == "object" and (.data != null) then
        (.data | if type == "array" then . else [.] end)
      else [] end;
    def has_vztmpl: (.content // "") | test("vztmpl");
    def store_id: .storage // .storeid // .id // "";
    unwrap | pve_array
    | map(select(store_id == $s) | select(has_vztmpl)
        | select((.type // "") == "dir" or (.type // "") == "nfs" or (.type // "") == "cifs"))
    | length
  ')
  [[ "${n:-0}" =~ ^[0-9]+$ && "$n" -gt 0 ]]
}

# One storage id per line: vztmpl + type dir|nfs|cifs on this node (same rule as oci-registry-pull).
oci_pull_template_storage_ids() {
  local json="${STORAGE_JSON_CACHED:-}"
  printf '%s\n' "$json" | jq -r '
    def unwrap: if type == "string" and test("^\\s*\\{") then fromjson else . end;
    def pve_array:
      if type == "array" then .
      elif type == "object" and (.data != null) then
        (.data | if type == "array" then . else [.] end)
      else [] end;
    def has_vztmpl: (.content // "") | test("vztmpl");
    unwrap | pve_array
    | map(select(has_vztmpl)
        | select((.type // "") == "dir" or (.type // "") == "nfs" or (.type // "") == "cifs"))
    | (.[] | (.storage // .storeid // .id) // empty)
  ' | sort -u | sed '/^$/d;/^null$/d'
}

pick_template_storage_or_exit() {
  load_node_storage_json
  STORAGE="${STORAGE#"${STORAGE%%[![:space:]]*}"}"
  STORAGE="${STORAGE%"${STORAGE##*[![:space:]]}"}"
  if [[ -z "$STORAGE" ]]; then
    local -a cands=()
    mapfile -t cands < <(oci_pull_template_storage_ids)
    if [[ "${#cands[@]}" -eq 1 ]]; then
      STORAGE="${cands[0]}"
      echo "Note: auto-selected --storage '${STORAGE}' (only vztmpl+oci-registry-pull candidate on node '${NODE}')." >&2
    elif [[ "${#cands[@]}" -eq 0 ]]; then
      echo "No storage on node '${NODE}' is usable for oci-registry-pull (need vztmpl + type dir, nfs, or cifs)." >&2
      echo >&2
      list_template_storages
      echo >&2
      echo "Enable **Container template** on a dir/nfs/cifs store, then re-run (or pass --storage explicitly)." >&2
      exit 2
    else
      echo "--storage not set; multiple OCI template candidates on node '${NODE}' — pick one:" >&2
      echo >&2
      list_template_storages
      echo >&2
      echo "Re-run with:  --storage <storage id from above where oci-registry-pull is yes>" >&2
      exit 2
    fi
  fi
  if ! template_storage_valid_for_oci_pull "$STORAGE"; then
    echo "Invalid --storage '${STORAGE}' for oci-registry-pull (not found on this node, or no vztmpl, or type is not dir/nfs/cifs)." >&2
    echo >&2
    list_template_storages
    echo >&2
    echo "Re-run with:  --storage <storage id from above where oci-registry-pull is yes>" >&2
    exit 2
  fi
}

pick_template_storage_or_exit

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

# Host path under vztmpl exists only for storages with a directory-style layout (e.g. "dir", some NFS).
# ZFS pools, LVM-thin, RBD, etc. return "storage definition has no path" from get_vztmpl_dir — that is normal.
vztmpl_host_dir_for_storage() {
  local sid="$1" out
  out="$(perl -MPVE::Storage -e 'print PVE::Storage::get_vztmpl_dir(PVE::Storage::config(), $ARGV[0]) . "\n"' "$sid" 2>/dev/null)" || return 1
  out="${out//$'\r'/}"
  out="${out//$'\n'/}"
  [[ -n "$out" && -d "$out" ]] || return 1
  printf '%s\n' "$out"
}

# True if vztmpl volume id exists on this storage (works when there is no single host path).
storage_has_ostemplate_volid() {
  local json want="${STORAGE}:vztmpl/${NORM}.tar" n
  json=$(pvesh get "/nodes/${NODE}/storage/${STORAGE}/content" --output-format json 2>/dev/null) || return 1
  printf '%s\n' "$json" | jq -e . >/dev/null 2>&1 || return 1
  n=$(printf '%s\n' "$json" | jq -r --arg v "$want" '
    def unwrap: if type == "string" and test("^\\s*\\{") then fromjson else . end;
    def pve_array:
      if type == "array" then .
      elif type == "object" and (.data != null) then
        (.data | if type == "array" then . else [.] end)
      else [] end;
    try (
      unwrap | pve_array
      | map(select((.volid // "") == $v))
      | length
    ) catch empty
  ' 2>/dev/null) || return 1
  [[ "${n:-0}" =~ ^[0-9]+$ && "$n" -gt 0 ]]
}

wait_until_ostemplate_visible() {
  local i
  if [[ -n "${LOCAL_TAR:-}" && -f "$LOCAL_TAR" ]]; then
    return 0
  fi
  for ((i = 0; i < 20; i++)); do
    storage_has_ostemplate_volid && return 0
    sleep 1
  done
  return 1
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

# pvesh create sometimes prints a bare UPID line or mixes stderr; avoid jq on non-JSON.
parse_upid_from_create_response() {
  local raw="$1" upid
  upid=$(printf '%s\n' "$raw" | grep -oE 'UPID:[^[:space:]]+' | tail -1)
  if [[ -n "$upid" ]]; then
    printf '%s\n' "$upid"
    return 0
  fi
  upid=$(printf '%s\n' "$raw" | jq -r '
    try (
      (if type == "string" and test("^\\s*\\{") then fromjson else . end)
      | if type == "object" and (.data != null) then .data else . end
      | if type == "string" then . elif type == "number" then tostring else empty end
    ) catch empty
  ' 2>/dev/null) || true
  if [[ -n "$upid" && "$upid" != "null" ]]; then
    printf '%s\n' "$upid"
    return 0
  fi
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*\{ ]] || continue
    upid=$(printf '%s\n' "$line" | jq -r '
      try (
        (if type == "string" and test("^\\s*\\{") then fromjson else . end)
        | if type == "object" and (.data != null) then .data else . end
        | if type == "string" then . elif type == "number" then tostring else empty end
      ) catch empty
    ' 2>/dev/null) || true
    if [[ -n "$upid" && "$upid" != "null" ]]; then
      printf '%s\n' "$upid"
      return 0
    fi
  done <<< "$(printf '%s\n' "$raw")"
  return 1
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
    if echo "$out" | grep -qiE 'not a file based storage|zfspool'; then
      echo >&2
      echo "oci-registry-pull only supports the same storages the UI can write an OCI .tar to (dir, nfs, cifs, …), not zfspool." >&2
      echo "Pass the Datacenter → Storage **id** where your Container templates path lives (vztmpl on your mount), not your CT disk pool:" >&2
      echo "  $0 --list-template-storages" >&2
      echo "Then e.g.:  --storage <that-id> --reference ${ref} --rootfs Storage:8 ..." >&2
    else
      echo "Hint: storage '${STORAGE}' must have vztmpl content; skopeo must exist at /usr/bin/skopeo; PVE must expose oci-registry-pull." >&2
    fi
    die "pvesh oci-registry-pull failed."
  }

  upid="$(parse_upid_from_create_response "$out" || true)"
  [[ -n "$upid" ]] || die "Could not parse UPID from pvesh output (expected JSON with .data or a UPID: line): $out"

  echo "Worker UPID: ${upid}"
  echo "Waiting for pull to finish..."
  wait_for_task "$upid"
  echo "Pull completed OK."
  echo
}

NORM="$(normalize_content_filename "$REFERENCE")"
OSTEMPLATE="${STORAGE}:vztmpl/${NORM}.tar"
LOCAL_TAR=""
VZTDIR=""
if VZTDIR="$(vztmpl_host_dir_for_storage "$STORAGE")"; then
  LOCAL_TAR="${VZTDIR}/${NORM}.tar"
else
  echo "Note: storage '${STORAGE}' has no resolvable host vztmpl path (typical for ZFS/LVM/RBD pools)." >&2
  echo "      Using storage API to detect ${OSTEMPLATE}; pct create still uses that volid." >&2
  echo >&2
fi

if [[ "$SKIP_PULL" -eq 1 ]]; then
  echo "Skipping pull (--skip-pull). Using ostemplate: ${OSTEMPLATE}"
elif [[ "$REUSE_LOCAL" -eq 1 ]]; then
  if [[ -n "$LOCAL_TAR" && -f "$LOCAL_TAR" ]]; then
    echo "Reusing existing template file: ${LOCAL_TAR}"
  elif storage_has_ostemplate_volid; then
    echo "Reusing existing template on storage (volid ${OSTEMPLATE})."
  else
    oci_registry_pull "$REFERENCE"
  fi
else
  oci_registry_pull "$REFERENCE"
fi

if [[ -n "$LOCAL_TAR" && -f "$LOCAL_TAR" ]]; then
  echo "Template on disk: ${LOCAL_TAR}"
  ls -lh "$LOCAL_TAR" 2>/dev/null || stat "$LOCAL_TAR" 2>/dev/null || true
elif wait_until_ostemplate_visible; then
  echo "Template visible on storage: ${OSTEMPLATE}"
else
  die "Template not found as ${OSTEMPLATE} (no file at ${LOCAL_TAR:-<no host path>} and storage content listing did not show it)."
fi
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
  if [[ ! "$mp_spec" =~ ^([^:]+):([0-9]+(\.[0-9]+)?):(/.*)$ ]]; then
    die "Invalid --mp '${mp_spec}' (expected STORAGE:SIZE:/path — absolute path inside CT; SIZE is GiB, integer or decimal e.g. 8 or 0.25)"
  fi
  mp_st="${BASH_REMATCH[1]}"
  mp_sz="${BASH_REMATCH[2]}"
  mp_path="${BASH_REMATCH[4]}"
  awk -v s="$mp_sz" 'BEGIN { exit !(s > 0) }' || die "Invalid --mp '${mp_spec}': size must be > 0"
  cmd+=( "--mp${mp_idx}" "${mp_st}:${mp_sz},mp=${mp_path}" )
  mp_idx=$((mp_idx + 1))
done
unset mp_st mp_sz mp_path mp_spec 2>/dev/null || true

echo "Running:"
printf ' '; printf '%q ' "${cmd[@]}"; echo; echo
"${cmd[@]}" || die "pct create failed"

echo
echo "pct create OK. Start with: pct start ${VMID}"
