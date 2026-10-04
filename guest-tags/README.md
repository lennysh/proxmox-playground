# guest-tags

Add Proxmox tags to QEMU VMs or LXC containers **without replacing** the existing
tag list. The script detects guest type from cluster config, so you do not need
to pick `qm` vs `pct`.

## Quick start

On any cluster node:

```bash
cd guest-tags

# Preview
sudo ./scripts/add-guest-tag.sh -v 100 -t no-backup -d

# Add (keeps any tags already on the guest)
sudo ./scripts/add-guest-tag.sh -v 100 -t no-backup

# Several guests / tags
sudo ./scripts/add-guest-tag.sh -v 100,101 -t no-backup
sudo ./scripts/add-guest-tag.sh -v 9000 -t backup-stop
```

## Directory structure

```
guest-tags/
├── README.md
└── scripts/add-guest-tag.sh
```

## Script

### add-guest-tag.sh

| Option | Description |
|--------|-------------|
| `-v`, `--vmid` | Guest ID (repeat or comma-separated) |
| `-t`, `--tag` | Tag to add (repeat for more than one) |
| `-d`, `--dry-run` | Print the resulting list; do not write |
| `--verbose` | Extra logging |
| `-h`, `--help` | Usage |

Type detection, in order:

1. `/etc/pve/qemu-server/<vmid>.conf` → QEMU (`qm set`)
2. `/etc/pve/lxc/<vmid>.conf` → LXC (`pct set`)
3. `pvesh get /cluster/resources --type vm` if the conf files are not visible

Configs live in pmxcfs, so this works from **any node** even when the guest
runs elsewhere.

If the tag is already present, that guest is left unchanged (not an error).

## Requirements

- Proxmox VE 7+
- Root for writes (`-d` can run unprivileged if `/etc/pve` is readable)
- `qm` / `pct` on the node

## See also

- [backup-tags](../backup-tags/README.md) — rewrite a backup job from these tags
- [Root README](../README.md)
