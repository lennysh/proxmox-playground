# OCI LXC rootfs refresh (`oci-ct-refresh-rootfs.sh`)

Proxmox VE 9.1+ can create LXC containers from **OCI** images (`oci://…`). There is no single built-in “upgrade this CT to a newer image digest” action yet. This script automates a practical pattern:

1. **Stop** the **existing** CT (same CTID, hostname, network, and **`mpX` bind mounts** stay in its config).
2. **`pct snapshot`** on that CT (required to succeed by default; quick rollback before any rsync).
3. Create a **temporary** CT from the **new** OCI image.
4. **Mount** both roots on the host and **`rsync`** the new root tree onto the old CT’s **rootfs** (with optional excludes for bind-mount paths inside the root volume).
5. **Destroy** the temp CT and **start** the original CT again.

Stateful data should live on **host bind mounts** (`mp0`, `mp1`, …) or separate volumes—not in random paths under `/` on the rootfs—because anything only on rootfs is replaced when you refresh.

## Requirements

- Run on the **Proxmox node** that owns the CT, as **root**.
- `pct`, `pvesh`, `rsync` available (normal on PVE).
- `jq` optional (used to parse `/cluster/nextid` JSON if present).

## Usage

```bash
chmod +x oci-ct-refresh-rootfs.sh   # once
./oci-ct-refresh-rootfs.sh [options] <old_ctid> <new_oci_ref> [temp_ctid]
```

**Options**

| Option | Description |
|--------|-------------|
| *(default)* | After stopping the CT, run **`pct snapshot`**. If it **fails**, the script **exits** (no rsync) so you never refresh without a rollback point. |
| `--allow-failed-snapshot` | Still run `pct snapshot`, but **continue** if it fails (e.g. directory storage, or a transient error you accept). |
| `--no-snapshot` | **Skip** `pct snapshot` entirely (lab only, or you handled backup/snapshot elsewhere). |

**Arguments**

| Argument      | Description |
|---------------|-------------|
| `old_ctid`    | The CT to keep (same ID, config, bind mounts). |
| `new_oci_ref` | New image reference, e.g. `oci://docker.io/library/nginx:latest`. |
| `temp_ctid`   | Optional. If omitted, uses the cluster **next free** VMID from `pvesh get /cluster/nextid`. |

**Examples**

```bash
./oci-ct-refresh-rootfs.sh 100 oci://ghcr.io/org/app:v2.3.1
./oci-ct-refresh-rootfs.sh --allow-failed-snapshot 100 oci://ghcr.io/org/app:v2.3.1
./oci-ct-refresh-rootfs.sh --no-snapshot 100 oci://ghcr.io/org/app:v2.3.1
```

## What is preserved vs replaced

| Preserved | Replaced |
|-----------|----------|
| CTID, `pct` settings that are not root content: CPU, RAM, net, hostname in config, features, etc. | Contents of **rootfs** (everything under `/` on the root volume that is not excluded). |
| All **`mpX:`** lines (bind mounts / additional volumes) in `/etc/pve/lxc/<id>.conf` | Default files on root that overlap with the new image. |

Anything you need across refreshes should be on **`mpX`** (or similar) or rebuilt by automation (e.g. cloud-init, first-boot scripts), not hand-edited only on rootfs.

## Implementation notes

- **Temp CT create** reuses **storage** and **size** parsed from the old CT’s `rootfs:` line. A new volume is allocated (`vm-<temp>-disk-*`); it is removed when the temp CT is destroyed.
- **`pct mount`** is used so both filesystems are visible on the host; the doc warns this **locks** the CT until `pct unmount`—keep the rsync window reasonable.
- Default **temp `net0`** is `bridge=vmbr0,ip=dhcp` so `pct create` succeeds without copying a full static layout. If your site requires static IPs at create time, edit the script to copy `net0` from `$OLD` (or pass equivalent options).
- **`rsync --delete`** makes the old root match the new image; paths listed as **`mp=`** targets on the old config get **`--exclude`** so the sync does not try to wipe those directory trees on the root volume (they are usually empty while stopped; excludes add a small safety margin).
- **Clusters**: the CT must be **local** to the node you run on. For remote nodes, run the script over SSH on that node (or extend the script).

## Snapshots vs full backups

**Built-in step: `pct snapshot`**

Proxmox can snapshot an LXC when the **managed** volumes (e.g. ZFS-backed `rootfs` / `mp` disks) support it. That gives you a **fast, local rollback** (`pct rollback <vmid> <snapname>`) if the refresh misbehaves. Snapshot names look like `pre-oci-refresh-YYYYMMDD-HHMMSSUTC`.

Important limitations:

- **Not a disaster-recovery copy**: snapshots usually live on the **same pool** as the CT. Pool or node loss can take snapshots with it.
- **Bind mounts** (`mpX` pointing at host paths) are **not** “inside” the root volume; the snapshot covers what Proxmox tracks for that CT’s disks, not arbitrary host directories. Your long-lived data on binds is still on those host paths (unchanged by this script), but “undo the whole machine” DR is a different story than `pct rollback`.

**Manual / scheduled: `vzdump` or Proxmox Backup Server**

For **long-term restore** (another node, older point in time, compliance), keep using **backup jobs** (`vzdump`, PBS, etc.). That is the right place for retention, dedupe, and off-site copies.

**Practical split**

| Goal | Use |
|------|-----|
| “Undo this refresh in seconds if rsync or the new image breaks” | `pct snapshot` (script **requires** success unless you opt out) |
| “Restore after disk death or rebuild a cluster” | Regular **vzdump/PBS** (and test restores) |

You can use **both**: default snapshot for quick rollback, plus your normal backup policy unchanged.

## Alternatives

- **Recreate** the CT from the new image and reattach the same `mpX` host paths (no rsync); more typing, same idea.
- **`pct move-volume`** may allow volume moves between CTs on some setups; behavior depends on storage type and whether `rootfs` can be reassigned without a full recreate. The rsync approach is storage-agnostic.

## Files

| File | Role |
|------|------|
| `oci-ct-refresh-rootfs.sh` | Executable refresh workflow. |
| `OCI_CT_ROOTFS_REFRESH.md` | This document. |
