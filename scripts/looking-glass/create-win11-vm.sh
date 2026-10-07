#!/bin/bash
# scripts/looking-glass/create-win11-vm.sh
#
# Defines and boots a Windows 11 libvirt VM wired up for Looking Glass (IDD):
# q35 + UEFI (no Secure Boot, see below) + emulated TPM, virtio disk/net, SPICE fallback
# display/clipboard/audio, a QEMU guest agent channel, and an IVSHMEM device
# backed by /dev/kvmfr0.
# There's no GPU passthrough (iGPU-only laptop), so the IDD runs in software mode.
#
# Prerequisites: `ansible-playbook custom-installers.yml --tags looking_glass -K`
# (kvmfr module, swtpm, AppArmor/cgroup rules) — see README.md alongside.
#
# Usage: scripts/looking-glass/create-win11-vm.sh WIN11_ISO VIRTIO_WIN_ISO
#   WIN11_ISO       https://www.microsoft.com/software-download/windows11
#   VIRTIO_WIN_ISO  https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#
# Secure Boot is OFF: on this host (OVMF 2025.11 Ubuntu and 2026.02 nixpkgs
# builds, QEMU 10.2, kernel 7.0, Ryzen 7840U) every SMM/Secure-Boot firmware
# build hangs the Win11 23H2 ISO's boot manager right after "Press any key to
# boot from CD" (BSP spins with interrupts off, ISO reads stop at 3.5 MB),
# while the plain OVMF_CODE_4M.fd boots setup in seconds. Win11 setup then needs
# its Secure Boot check bypassed — see README.md step 4.
#
# Overridable via env: VM_NAME (win11), VCPUS (8), RAM_MIB (16384),
# DISK_GB (120), DRY_RUN=1 to only print the generated domain XML.

set -euo pipefail

WIN_ISO="${1:?usage: $0 WIN11_ISO VIRTIO_WIN_ISO}"
VIRTIO_ISO="${2:?usage: $0 WIN11_ISO VIRTIO_WIN_ISO}"

VM_NAME="${VM_NAME:-win11}"
VCPUS="${VCPUS:-8}"          # 4 cores × 2 threads; leaves 4c/8t for the host
RAM_MIB="${RAM_MIB:-16384}"
DISK_GB="${DISK_GB:-120}"
DISK_PATH="$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2"

# Must equal static_size_mb the module was loaded with (kvmfr doesn't expose
# it in sysfs), so read the Ansible-managed modprobe config (MiB → bytes).
KVMFR_SIZE_MB="$(sed -n 's/.*static_size_mb=\([0-9]*\).*/\1/p' /etc/modprobe.d/kvmfr.conf 2>/dev/null)"
KVMFR_SIZE_BYTES=$(( ${KVMFR_SIZE_MB:-64} * 1024 * 1024 ))

# ── Sanity checks ──────────────────────────────────────────────────────────
for f in "$WIN_ISO" "$VIRTIO_ISO"; do
    [[ -f "$f" ]] || { echo "error: $f not found" >&2; exit 1; }
done

# If QEMU starts before the module is loaded it creates /dev/kvmfr0 as a
# regular file, which then shadows the char device forever after.
if [[ ! -c /dev/kvmfr0 ]]; then
    echo "error: /dev/kvmfr0 is not a character device." >&2
    [[ -e /dev/kvmfr0 ]] && echo "  It exists as a regular file — stop all VMs, sudo rm /dev/kvmfr0, then sudo modprobe kvmfr." >&2
    echo "  Run: ansible-playbook custom-installers.yml --tags looking_glass -K" >&2
    exit 1
fi
[[ -r /dev/kvmfr0 && -w /dev/kvmfr0 ]] || echo "warning: no rw access to /dev/kvmfr0 for $USER yet (udev uaccess applies at next login/replug)" >&2

if [[ "${DRY_RUN:-0}" != 1 ]] && virsh -c qemu:///system dominfo "$VM_NAME" &>/dev/null; then
    echo "error: VM '$VM_NAME' already exists (virsh -c qemu:///system undefine --nvram --tpm $VM_NAME to remove)" >&2
    exit 1
fi

mkdir -p "$(dirname "$DISK_PATH")"

# ── Define + start ─────────────────────────────────────────────────────────
# --qemu-commandline values are shlex-split by virt-install, hence the inner
# single quotes around the JSON (JSON -device/-object syntax: QEMU ≥ 6.2 +
# libvirt ≥ 7.9, which also avoids the legacy-syntax PCI slot clash).
# shellcheck disable=SC2054  # commas are virt-install sub-option syntax
args=(
    --connect qemu:///system
    --name "$VM_NAME"
    --osinfo win11
    --machine q35
    # Explicit loader: with secure-boot=no, libvirt's firmware autoselect on an
    # AMD host picks the SEV build (OVMF.amdsev.fd), which virt-aa-helper rejects.
    --boot loader=/usr/share/OVMF/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.fd
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb
    --cpu host-passthrough,cache.mode=passthrough,topology.sockets=1,topology.cores=$((VCPUS / 2)),topology.threads=2,require=topoext
    --vcpus "$VCPUS"
    --memory "$RAM_MIB"
    --memballoon none
    --disk "path=$DISK_PATH,size=$DISK_GB,format=qcow2,bus=virtio,cache=none,discard=unmap"
    --cdrom "$WIN_ISO"
    --disk "path=$VIRTIO_ISO,device=cdrom,bus=sata"
    --network network=default,model=virtio
    --graphics spice
    --video vga
    --channel spicevmc,target.type=virtio,target.name=com.redhat.spice.0
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
    --sound ich9,audio.id=1
    --audio type=spice,id=1
    --qemu-commandline="-device '{\"driver\":\"ivshmem-plain\",\"id\":\"shmem0\",\"memdev\":\"looking-glass\"}'"
    --qemu-commandline="-object '{\"qom-type\":\"memory-backend-file\",\"id\":\"looking-glass\",\"mem-path\":\"/dev/kvmfr0\",\"size\":$KVMFR_SIZE_BYTES,\"share\":true}'"
    --noautoconsole
)

if [[ "${DRY_RUN:-0}" == 1 ]]; then
    virt-install "${args[@]}" --print-xml --dry-run
    exit 0
fi

virt-install "${args[@]}"

cat <<EOF

VM '$VM_NAME' created and booting. Open it in virt-manager (SPICE console) NOW
and press a key at "Press any key to boot from CD or DVD" (it times out in ~5s;
if missed: Force Off, then Run, and press a key). Then follow step 4 of
scripts/looking-glass/README.md (Secure Boot check bypass, virtio disk driver).
EOF
