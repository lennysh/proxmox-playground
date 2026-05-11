# Create an LXC from an OCI registry image (`oci-ct-create-from-registry.sh`)

Proxmox VE can store OCI images as **container templates** on storage that has the **vztmpl** content type. The web UI uses the storage API **`oci-registry-pull`**, which runs the same `skopeo` copy the UI documents internally: `docker://<reference>` → `oci-archive:<vztmpl-dir>/<normalized>.tar`.

This script does that pull (via **`pvesh create …/oci-registry-pull`**, then waits for the worker task), then **`pct create`** using the resulting **`STORAGE:vztmpl/<name>.tar`** volume id—matching the UI flow: download to template storage, then create from that template.

## Requirements

- Proxmox VE with **`POST /nodes/{node}/storage/{storage}/oci-registry-pull`** (same generation as OCI-as-template in the UI; typically PVE **9.x** with current storage stack).
- Run on a **cluster node** as **root** (local `pvesh` / `pct`).
- **`jq`** (used for JSON from `pvesh` and task status polling).
- **`skopeo`** on the node (the API refuses the call if `/usr/bin/skopeo` is missing).
- **`--storage`** must be **file-based** storage with **`vztmpl`** enabled (same constraint as the UI).

## Usage

```bash
chmod +x oci-ct-create-from-registry.sh
./oci-ct-create-from-registry.sh --help
```

Typical create:

```bash
./oci-ct-create-from-registry.sh \
  --storage local \
  --reference docker.io/library/nginx:latest \
  --rootfs local-zfs:8 \
  --hostname my-nginx-ct
```

Template-only download (no CT):

```bash
./oci-ct-create-from-registry.sh \
  --storage local \
  --reference ghcr.io/org/app:1.2.3 \
  --pull-only
```

## Options (summary)

| Option | Meaning |
|--------|--------|
| `--storage ID` | Template storage (must allow **vztmpl**). |
| `--reference REF` | Image reference for the API (e.g. `docker.io/library/alpine:3.21`). Leading `oci://` or `docker://` is stripped. |
| `--rootfs SPEC` | New CT disk: **`STORAGE:GiB`** integer (e.g. `local-zfs:8`). Not used with **`--pull-only`**. |
| `--vmid ID` | Optional; default is cluster next free (`pvesh get /cluster/nextid`). |
| `--hostname` | Optional; default `oci-ct-<vmid>`. |
| `--net0` | Optional; default `name=eth0,bridge=vmbr0,ip=dhcp` or env **`OCI_CT_CREATE_NET0`**. |
| `--node` | Optional; default `pvecm nodename` or short hostname. |
| `--skip-pull` | Use an existing template on disk (must match normalized name for **`--reference`**). |
| `--reuse-local-template` | Skip pull if **`…/vztmpl/<normalized>.tar`** already exists. |
| `--pull-only` | Download template only; no **`pct create`**. |

## Implementation notes

- **Normalized filename** is computed with **`PVE::Storage::normalize_content_filename`** via the same Perl API Proxmox ships, plus **`.tar`**—identical to the **`oci-registry-pull`** implementation.
- **`pct create`** is given **`STORAGE:vztmpl/<normalized>.tar`**, not a raw **`oci://`** URL, so the Proxmox “first colon is storage” parsing issue does not apply (see `oci_ct_rootfs_refresh` for background on **`oci://`** and **`pct`**).
- The pull runs as an **async worker**; the script polls **`/nodes/{node}/tasks/{upid}/status`** until **`stopped`** with **`exitstatus`** **`OK`**.
- Private registries: configure auth the same way as for the UI / **`skopeo`** (e.g. **`skopeo login ghcr.io`**, or **`/root/.config/containers/auth.json`**).

## Related

- **`oci_ct_rootfs_refresh/`** — refresh an **existing** CT’s rootfs from a new image (rsync pattern), including a **`skopeo`** workaround when **`pct`** is given a local tar.
