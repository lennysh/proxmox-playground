# Create an LXC from an OCI registry image (`oci-ct-create-from-registry.sh`)

Proxmox VE can store OCI images as **container templates** on storage that has the **vztmpl** content type. The web UI uses the storage API **`oci-registry-pull`**, which runs the same `skopeo` copy the UI documents internally: `docker://<reference>` → `oci-archive:<vztmpl-dir>/<normalized>.tar`.

This script does that pull (via **`pvesh create …/oci-registry-pull`**, then waits for the worker task), then **`pct create`** using the resulting **`<template-storage>:vztmpl/<name>.tar`** volume id—matching the UI: the image lands under **whatever Datacenter → Storage entry** holds **Container template** content (often a **dir** or **nfs** mount), then the CT is created from that same volid.

## Requirements

- Proxmox VE with **`POST /nodes/{node}/storage/{storage}/oci-registry-pull`** (same generation as OCI-as-template in the UI; typically PVE **9.x** with current storage stack).
- Run on a **cluster node** as **root** (local `pvesh` / `pct`).
- **`jq`** (used for JSON from `pvesh` and task status polling).
- **`skopeo`** on the node (the API refuses the call if `/usr/bin/skopeo` is missing).
- **`--storage`** must be the **same storage id** you would pick in the UI for OCI / container templates: a Datacenter → Storage entry whose **content** includes **vztmpl**, and whose **type** supports **`oci-registry-pull`** (typically **`dir`**, **`nfs`**, **`cifs`** — **not** a **`zfspool`** id used only for CT disks).

### Which `--storage` id is that?

It is **your** Proxmox storage id for **Container templates** (mounted NFS, `dir` under `/mnt/pve/…`, etc.) — the same id the UI uses when it stores an OCI image there. You can run **`--list-template-storages`**, or omit **`--storage`** / pass a wrong id and the script will **list candidates and exit 2** so you can copy a valid id. Your zfspool (e.g. **`Storage`**) stays on **`--rootfs`** / **`--mp`**.

### ZFS pool for the CT but templates on a mount

```bash
./oci-ct-create-from-registry.sh \
  --storage nfs-proxmox \
  --reference docker.io/library/nginx:latest \
  --rootfs Storage:8 \
  --mp Storage:0.25:/var/cache/nginx \
  --mp Storage:0.25:/mnt/media
```

(`nfs-proxmox` is an example id — substitute the id from **`--list-template-storages`**.)

## Usage

```bash
chmod +x oci-ct-create-from-registry.sh
./oci-ct-create-from-registry.sh --help
./oci-ct-create-from-registry.sh --list-template-storages
```

Typical create:

```bash
./oci-ct-create-from-registry.sh \
  --storage nfs-proxmox \
  --reference docker.io/library/nginx:latest \
  --rootfs Storage:8 \
  --hostname my-nginx-ct
```

Template-only download (no CT):

```bash
./oci-ct-create-from-registry.sh \
  --storage nfs-proxmox \
  --reference ghcr.io/org/app:1.2.3 \
  --pull-only
```

## Options (summary)

| Option | Meaning |
|--------|--------|
| `--storage ID` | **Optional.** Template / vztmpl storage id (same as Datacenter → Storage in the UI). If omitted and **exactly one** node storage matches vztmpl + dir\|nfs\|cifs, that id is **auto-selected**. If **zero** or **multiple** matches, the script **prints the list** and exits **2**. If you pass an id that does not match, same list + exit **2**. |
| `--list-template-storages` | Lists node storages that include **vztmpl** and marks which accept **`oci-registry-pull`** (same rule as the UI). No other flags required. |
| `--reference REF` | Image reference for the API (e.g. `docker.io/library/alpine:3.21`). Leading `oci://` or `docker://` is stripped. Floating `:latest` is resolved before pull (see below). |
| *(env)* `OCI_CT_CREATE_NO_RESOLVE_LATEST=1` | Keep `--reference` exactly as given (including `:latest` and `*_latest.tar` names). |
| `--rootfs SPEC` | New CT disk: **`STORAGE:GiB`** integer (e.g. `local-zfs:8`). Not used with **`--pull-only`**. |
| `--vmid ID` | Optional; default is cluster next free (`pvesh get /cluster/nextid`). |
| `--hostname` | Optional; default `oci-ct-<vmid>`. |
| `--net0` | Optional; default `name=eth0,bridge=vmbr0,ip=dhcp` or env **`OCI_CT_CREATE_NET0`**. |
| `--node` | Optional; default `pvecm nodename` or short hostname. |
| `--skip-pull` | Use an existing template on disk (must match normalized name for **`--reference`**). |
| `--reuse-local-template` | Skip pull if **`…/vztmpl/<normalized>.tar`** already exists. |
| `--pull-only` | Download template only; no **`pct create`**. |
| `--mp SPEC` | Repeatable. Extra disk + mount inside the CT: **`STORAGE:GiB:/path`** (e.g. `local-zfs:64:/var/lib/postgresql/data`). Allocates a new volume like **`--rootfs`** and passes **`pct --mp0 …,mp=/path`**, then **`--mp1`**, … in order. |

**`--mp` details**

- **`STORAGE`** must allow LXC rootdir-style volumes (same classes of storage you use for **`--rootfs`**).
- **`GiB`** is a plain integer in gibibytes, matching **`pct create`** expectations for new volumes (not a `32G` suffix string).
- **`/path`** is the **guest** mount point (must be absolute). Proxmox creates the mount point entries **`mp0`**, **`mp1`**, … automatically.
- **`SIZE`** may be an integer or a decimal (e.g. **`0.25`** GiB), as long as **`pct create`** accepts it for that storage backend.

## ZFS / pool storage and “no path”

If Perl prints **`storage definition has no path`** when resolving the vztmpl directory, that usually means the template storage is **not** a simple directory backend (e.g. it is a **ZFS** pool, LVM-thin, RBD, …). That is **normal**: there is no single host path to `test -f` the `.tar`.

Current script behaviour:

- It **does not abort** anymore; it lists **`/nodes/<node>/storage/<storage>/content`** until **`STORAGE:vztmpl/<normalized>.tar`** appears (after **`oci-registry-pull`**), then runs **`pct create`** with that volid.

**Note:** Proxmox’s **`oci-registry-pull`** API **rejects `zfspool`** for the pull target. That is a product limitation, not this script. Use **`--list-template-storages`** to pick the template storage id (same as the UI), and **`--rootfs` / `--mp`** for ZFS (or any) CT disks.

## Floating `:latest` and template filenames

Proxmox names the vztmpl tarball from **`normalize_content_filename(reference)`**. A **`…:latest`** ref therefore becomes **`…_latest.tar`**, which does not tell you which build you have and makes “skip pull on existing file” unsafe when the registry moves **`latest`**.

Before **`oci-registry-pull`**, this script detects “floating latest” when:

- the ref ends in **`:latest`** (case-insensitive), or  
- **`normalize_content_filename`** would end in **`_latest`**

and then:

1. Runs **`skopeo inspect`** on your ref, then **`skopeo inspect`** on **`name@digest`** for that manifest.  
2. If the registry lists any **non-`latest`** tag for that digest, it picks the **highest `sort -V`** tag and pulls **`name:thatTag`** (API-friendly **`:tag`** form, human-readable tarball name).  
3. Otherwise it uses **`name@sha256:…`** for the pull. Proxmox’s API regex is **`:tag`-only** on some versions, so if **`pvesh`** rejects that reference **and** the template storage has a resolvable host vztmpl directory, the script falls back to **`skopeo copy`** straight to the same **`.tar`** path **`oci-registry-pull`** would have produced (same **`NORM`** as from Perl **`normalize_content_filename`** on the digest ref).

To keep legacy behaviour (no resolution), set **`OCI_CT_CREATE_NO_RESOLVE_LATEST=1`**.

## Existing template `.tar` (refusing to override)

If **`oci-registry-pull`** fails with **refusing to override existing file** (or similar), **`skopeo`** will not replace an **`oci-archive`** that already exists. If the expected **`STORAGE:vztmpl/<normalized>.tar`** is already present, this script **skips the pull** and continues with **`pct create`** using that template. With floating **`latest`** resolved as above, “existing file” now matches a **specific tag or digest-shaped name**, not a stale ambiguous **`_latest`** file. To force a fresh download, remove or rename the existing **`.tar`** in that storage’s vztmpl area (Datacenter → Storage → the template store → content), then re-run.

## Implementation notes

- **Normalized filename** is computed with **`PVE::Storage::normalize_content_filename`** via the same Perl API Proxmox ships, plus **`.tar`**—identical to the **`oci-registry-pull`** implementation.
- **`pct create`** is given **`STORAGE:vztmpl/<normalized>.tar`**, not a raw **`oci://`** URL, so the Proxmox “first colon is storage” parsing issue does not apply (see `oci_ct_rootfs_refresh` for background on **`oci://`** and **`pct`**).
- The pull runs as an **async worker**; the script polls **`/nodes/{node}/tasks/{upid}/status`** until **`stopped`** with **`exitstatus`** **`OK`**.
- Private registries: configure auth the same way as for the UI / **`skopeo`** (e.g. **`skopeo login ghcr.io`**, or **`/root/.config/containers/auth.json`**).

## Related

- **`oci_ct_rootfs_refresh/`** — refresh an **existing** CT’s rootfs from a new image (rsync pattern), including a **`skopeo`** workaround when **`pct`** is given a local tar.
