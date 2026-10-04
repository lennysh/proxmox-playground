# guest-tags

Add Proxmox tags to QEMU VMs or LXC containers **without replacing** the existing
tag list. The script finds the guest on **any cluster node** and updates it with
`pvesh` (local `qm`/`pct` only see guests on the node you are on).

## Quick start

On any cluster node:

```bash
cd guest-tags

sudo ./scripts/add-guest-tag.sh -v 134 -t no-backup -d
sudo ./scripts/add-guest-tag.sh -v 134 -t no-backup

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

Type/node detection:

1. Scan `/etc/pve/nodes/<node>/qemu-server/<vmid>.conf` and
   `/etc/pve/nodes/<node>/lxc/<vmid>.conf` (cluster filesystem)
2. Fall back to `pvesh get /cluster/resources --type vm`

Then: `pvesh set /nodes/<node>/{qemu|lxc}/<vmid>/config --tags …`

`/etc/pve/lxc` and `/etc/pve/qemu-server` are **this node only**. Using `pct` or
`qm` from another node produces `Configuration file 'nodes/<here>/lxc/<id>.conf'
does not exist`.

If the tag is already present, that guest is left unchanged (not an error).
If the same VMID has configs on two nodes, the script refuses to write (clean
up the leftover first).

## Requirements

- Proxmox VE 7+
- Root for writes
- `pvesh` (any cluster node)

## See also

- [backup-tags](../backup-tags/README.md) — rewrite a backup job from these tags
- [Root README](../README.md)
