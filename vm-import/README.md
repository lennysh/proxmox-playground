# VM Import - QCOW2 to ZFS

Import qcow2 disk images into Proxmox VMs using ZFS storage.

## Overview

This collection provides scripts for importing virtual disk images (qcow2, raw, vmdk) into Proxmox VMs. When using ZFS storage, Proxmox creates a ZFS zvol and converts the image to the appropriate format automatically.

## Quick Start

```bash
cd vm-import

# Import to existing VM 100 (uses default storage: local-zfs)
sudo ./scripts/import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2

# Import with specific ZFS storage
sudo ./scripts/import-qcow2-zfs.sh -v 101 -i /mnt/backup/ubuntu.qcow2 -s local-zfs

# Import and set as boot disk
sudo ./scripts/import-qcow2-zfs.sh -v 102 -i ./debian.qcow2 --boot

# Dry-run to preview
sudo ./scripts/import-qcow2-zfs.sh -v 100 -i /path/to/disk.qcow2 -d
```

## Requirements

- Proxmox VE 7.0+ or 8.0+
- Root access on Proxmox host
- ZFS storage configured in Proxmox (e.g., `local-zfs`)
- `qm`, `pvesm`, `qemu-img` utilities

## Script Reference

### import-qcow2-zfs.sh

Imports a qcow2 (or raw/vmdk) disk image into a Proxmox VM on ZFS storage.

**Required arguments:**
- `-v, --vmid` - Proxmox VM ID
- `-i, --image` - Path to the disk image file

**Optional arguments:**
- `-s, --storage` - ZFS storage name (default: `local-zfs`)
- `-f, --format` - Source format: qcow2, raw, vmdk (default: qcow2)
- `-b, --bus` - Disk bus: scsi, sata, virtio (default: scsi)
- `--boot` - Set imported disk as boot device
- `-d, --dry-run` - Preview without making changes
- `-y, --yes` - Skip confirmation prompts
- `--verbose` - Verbose output

**List available storage:**
```bash
pvesm status
```

## How It Works

1. **Validation** - Checks that the source file exists, is readable, and is a valid disk image
2. **Storage** - Verifies the target ZFS storage is configured in Proxmox
3. **VM** - Creates the VM if it doesn't exist, stops it if running
4. **Import** - Runs `qm importdisk` which:
   - Creates a ZFS zvol in the target storage
   - Converts the source image to the appropriate format
   - Attaches the disk to the VM
5. **Boot** - Optionally sets the imported disk as the boot device

## Common Workflows

### Import from downloaded image
```bash
# Download appliance/cloud image, then import
wget https://example.com/ubuntu-24.04.qcow2
sudo ./scripts/import-qcow2-zfs.sh -v 200 -i ./ubuntu-24.04.qcow2 --boot
qm start 200
```

### Import to new VM
```bash
# Script will prompt to create VM if it doesn't exist
sudo ./scripts/import-qcow2-zfs.sh -v 300 -i /backup/migrated-disk.qcow2 -y
```

### Migrate from another hypervisor
```bash
# Export from source (e.g., VirtualBox, VMware) as qcow2
# Copy to Proxmox host, then:
sudo ./scripts/import-qcow2-zfs.sh -v 400 -i /mnt/nfs/vm-disk.qcow2 -s local-zfs --boot
```

## Troubleshooting

**Storage not found**
- Run `pvesm status` to list configured storage
- Default ZFS storage is often `local-zfs` (configured during Proxmox ZFS install)
- Add storage via Proxmox web UI: Datacenter → Storage → Add

**Import takes a long time**
- Conversion time depends on image size and storage speed
- Large images (100GB+) can take 30+ minutes
- Progress is shown during import

**VM must be stopped**
- Importing while VM is running can cause data corruption
- Script will prompt to stop the VM, or use `qm stop <vmid>` first

## See Also

- [Proxmox Storage: ZFS](https://pve.proxmox.com/wiki/Storage:_ZFS)
- [qm importdisk](https://pve.proxmox.com/pve-docs/qm.1.html) - Proxmox disk import command
