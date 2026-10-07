# Looking Glass (Windows 11 VM via signed IDD)

[Looking Glass](https://looking-glass.io/) shows a Windows VM's desktop in a low-latency window on the host. It copies frames through shared memory (IVSHMEM) instead of a network or SPICE stream. The new **signed Looking Glass IDD** (Indirect Display Driver) is the Windows-side server. It replaces the legacy Host app, needs no dummy plug or physical monitor, supports any resolution and refresh rate (it follows the client window), does HDR on Plasma, and works **without a passthrough GPU** (software mode). That last point is why it works on this iGPU-only Framework 13.

The IDD is bleeding-edge only for now. Upstream requires **the client, IDD and kvmfr module to all come from the same build**. Everything here is pinned to commit `236efcb155f952f5d7d9fcd5891a3060ad254e68` (`B7-826-236efcb1`, docs: https://looking-glass.io/docs/B7-826-236efcb1/).

## What lives where

| Piece | Managed by |
|-------|-----------|
| `looking-glass-client` (bleeding build) + `~/.config/looking-glass/client.ini` | Nix: `lookingGlassClient` in `nix/modules/packages.nix` |
| kvmfr kernel module (dkms), `/etc/modprobe.d` + `/etc/modules-load.d` config, udev rule, AppArmor + `qemu.conf` cgroup ACL for `/dev/kvmfr0`, swtpm, virsh, libvirtd enabled | Ansible: `looking_glass` tag in `custom-installers.yml` |
| Windows 11 VM definition (q35, UEFI without Secure Boot, TPM, virtio, SPICE fallback, QEMU guest agent channel, IVSHMEM on `/dev/kvmfr0`) | `create-win11-vm.sh` (one-shot) |
| IDD + IVSHMEM driver inside Windows | Manual, step 5 below |

IVSHMEM is 64 MiB, which covers resolutions up to 3440x1440 (this laptop panel is 2256x1504). If you need more, change `kvmfr_static_size_mb` in `custom-installers.yml`. `create-win11-vm.sh` reads the VM's `size` from `/etc/modprobe.d/kvmfr.conf`, but an already-defined VM has to be edited (`virsh edit win11`). Formula and table: `doc/install_libvirt.rst` upstream.

## Setup

1. **Host system side** (sudo): `ansible-playbook custom-installers.yml --tags looking_glass -K`. Then check:
   - `ls -l /dev/kvmfr0` shows a `c` (char device), group `kvm`.
   - `getfacl /dev/kvmfr0` lists your user. The uaccess ACL is applied at the next login if it isn't there yet.
2. **Client**: run `hms`. Check with `looking-glass-client --help | head -1`, which should print `B7-826-236efcb1`.
3. **VM**: download the Windows 11 ISO and [`virtio-win.iso`](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso), then run `scripts/looking-glass/create-win11-vm.sh ~/Downloads/Win11*.iso ~/Downloads/virtio-win.iso`. Defaults are 8 vCPU, 16 GiB RAM and a 120 GB disk; override with `VCPUS`, `RAM_MIB`, `DISK_GB` or `VM_NAME`. Add `DRY_RUN=1` to only print the XML.
4. **Install Windows** in virt-manager's console (`win11` → Open). Work through these in order:
   1. **Boot prompt:** open the console straight away, because the ISO's "Press any key to boot from CD or DVD" times out after about 5 s. If you miss it, see *"No bootable option or device was found"* under Troubleshooting. Alternatively, send the keypress from the host: `for i in $(seq 30); do virsh -c qemu:///system send-key win11 KEY_ENTER; sleep 1; done`. Repeated Enters also click through the language and "Install now" screens, so check where you've ended up.
   2. **Secure Boot bypass:** do this before clicking Next on the edition-selection screen. The VM has no Secure Boot (see *Why no Secure Boot* below), so Windows 11 setup refuses with "This PC can't run Windows 11" unless you bypass the check. Press **Shift+F10** and run `reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f`. Close the prompt and continue. TPM, CPU and RAM pass on their own.
   3. **Edition and install type:** pick the edition (Home is preselected; you probably want Pro), accept the licence and choose **Custom: Install Windows only**.
   4. **Disk driver:** the disk is virtio, so the disk list starts empty. Choose *Load driver* and pick `viostor\w11\amd64` from the virtio-win CD.
   5. **Network at "Let's connect you to a network"** (Next is greyed out): Windows has no driver for the virtio NIC. Press **Shift+F10** and run the line below. It finds the virtio CD whatever drive letter it got.

      ```
      for %d in (D E F G) do @if exist %d:\NetKVM\w11\amd64 pnputil /add-driver %d:\NetKVM\w11\amd64\*.inf /install
      ```

      It should report "Driver package added successfully". The wired connection appears within seconds and Next lights up. For a local account instead of a Microsoft account, run `OOBE\BYPASSNRO` in that prompt instead: the VM reboots, and this screen then offers *"I don't have internet"*. Install the NIC driver later with step 6.
   6. **Other drivers:** once you're at the desktop, run `virtio-win-guest-tools.exe` from the virtio-win CD. It installs the remaining virtio drivers, the QEMU guest agent and the SPICE agent.
   7. **Eject the ISOs** (optional): in virt-manager → Show virtual hardware → each SATA CDROM → Disconnect. The saved VM definition boots from the disk only, so leaving them in is harmless. If you used `--boot cdrom,hd` to recover from the timeout (Troubleshooting), set it back with `virt-xml -c qemu:///system win11 --edit --boot hd`.
5. **In the guest**, download `looking-glass-idd-setup.exe` from https://looking-glass.io/downloads, taking the **bleeding-edge build matching `236efcb1`**. Run it as administrator and tick **IVSHMEM Driver**, **Indirect Display Driver (IDD)** and, if offered, **Disable old host app**. Reboot if it asks. Optionally install [spice-guest-tools](https://www.spice-space.org/download.html#windows-binaries) for clipboard sync. A "Looking Glass" display and a tray helper should appear; the helper should report *software* processing (no GPU).
6. **Run `looking-glass-client`** on the host. Press Scroll Lock (the default escape key) to toggle input capture, or hold it for the shortcut list.

### Why no Secure Boot

On this host, every SMM/Secure Boot OVMF build tested hangs the Windows 11 23H2 ISO's boot manager straight after "Press any key to boot from CD". That covers Ubuntu's `OVMF_CODE_4M.secboot.fd` 2025.11, with and without Microsoft keys enrolled, and nixpkgs' `OVMFFull` 2026.02. The boot CPU spins with interrupts disabled and the ISO reads stop at 3.5 MB. Plain `OVMF_CODE_4M.fd` (still UEFI, still SMM, with a TPM) boots setup in about 6 s. Looking Glass doesn't need Secure Boot. Things that do need it (some anti-cheat) won't work in this VM. A newer Windows ISO or newer firmware may fix it: test with `virt-xml win11 --edit --boot firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,…` before relying on it.

## Updating

Bump all three together, or the client will refuse the IDD's protocol version:

1. In `nix/modules/packages.nix`, set `lookingGlassClient`'s `rev`, `version` (in both places) and `hash` (set it to `lib.fakeHash`, build, and copy the `got:` value). Then run `hms`.
2. In `custom-installers.yml`, set `looking_glass_rev` (and `kvmfr_version` if `module/dkms.conf` changed). Re-run the tag; the rev stamp in `/usr/src/kvmfr-*/` triggers a dkms rebuild.
3. In the guest, run the matching `looking-glass-idd-setup.exe` over the top.

The dkms module rebuilds itself on kernel upgrades (`AUTOINSTALL=yes`). The **host's** Secure Boot is currently off; if you turn it on, the unsigned module needs MOK signing.

## Troubleshooting

### Host and libvirt

- **`Unit libvirtd.service not found`** (Ansible's *enable + start libvirtd* task): the libvirt daemon isn't installed. `dpkg -l | grep libvirt-daemon` shows `rc` (removed, config left), not `ii`. An `apt autoremove` in 2026-03 removed it, because `virt-manager` comes from Nix and nothing on the apt side depended on the daemon. The playbook now installs `libvirt-daemon-system` explicitly, so re-run the tag.
- **`network 'default' is not active`** (from virt-install): reinstalling the daemon over leftover config doesn't reactivate the NAT network. The playbook handles this; to fix it by hand, run `virsh -c qemu:///system net-start default && virsh -c qemu:///system net-autostart default`.
- **`cannot load AppArmor profile 'libvirt-<uuid>'`**: check `journalctl --since -5min | grep virt-aa-helper`. If it names `OVMF.amdsev.fd` / "skipped restricted file", libvirt's firmware autoselect picked the AMD SEV build. That happens with `--boot uefi` plus `secure-boot=no` on an AMD host. Give an explicit loader path instead, as `create-win11-vm.sh` does (`--boot loader=/usr/share/OVMF/OVMF_CODE_4M.fd,…`).
- **`virt-aa-helper` "DENIED … win11.qcow2" in the kernel log**: this is harmless noise. libvirt's profile generator can't probe an image under `$HOME`, but QEMU itself is allowed and the VM runs.
- **A failed `create-win11-vm.sh` run**: virt-install deletes the disk it just allocated and leaves no VM defined, so after fixing the cause you can re-run it as is. If a VM *was* defined, the script refuses to continue. Remove it with `virsh -c qemu:///system undefine --nvram --tpm win11` (add `--remove-all-storage` to delete the disk too).

### Booting the installer

- **"BdsDxe: No bootable option or device was found"**: the CD prompt timed out before a key was pressed. Don't use virt-manager's *Reset* or `virsh reset` while virt-install's first boot is still running. That boot is set up as `on_reboot=destroy`, so a reset **shuts the VM off**, and the saved definition then boots from the (still empty) disk only. Instead, Force Off, put the CD first (`virt-xml -c qemu:///system win11 --edit --boot cdrom,hd`), then Run and press a key.
- **Screen frozen on "Press any key to boot from CD or DVD.." after pressing a key** (the dots stop, nothing happens for minutes): this is the Secure Boot firmware hang from *Why no Secure Boot*. Check whether the VM's firmware is the Secure Boot build with `virsh -c qemu:///system dumpxml win11 | grep loader`. To confirm it's this hang:
  - `virsh -c qemu:///system domblkstat win11 sda` shows `rd_bytes` stuck around 3.5 MB. A healthy setup boot reads more than 100 MB within seconds.
  - `virsh -c qemu:///system qemu-monitor-command win11 --hmp 'info registers' | grep -E 'RIP|RFL'` shows the same RIP on every sample, with `RFL=00000046` (interrupts disabled).
- **"Password sign-in isn't available. Try another method." at "Let's add your Microsoft account"**: the Microsoft account is passwordless (passkey or Authenticator only), so there's no password to type. Use one of these:
  - Go back with the top-left arrow, re-enter the email, and pick *Other ways to sign in*. Choose Authenticator approval or an emailed code. The 23H2 setup screens don't support passkeys.
  - Use a local account instead, and add the Microsoft account later in Settings → Accounts. Press Shift+F10 and run `OOBE\BYPASSNRO`. Once the network driver is installed, OOBE goes online again after the reboot, so before the network screen take the VM's link down from the host: `virsh -c qemu:///system domif-setlink win11 "$(virsh -c qemu:///system domiflist win11 | awk '/virtio/{print $1}')" down`. Choose *I don't have internet* → *Continue with limited setup*, then bring the link back `up` with the same command once you're at the desktop.
- **Windows 11 setup says "This PC can't run Windows 11"**: the `LabConfig` bypass from step 4.2 wasn't set before the compatibility check ran. Go back (the arrow at the top left), press Shift+F10, add the key, and continue.

### Looking Glass

- **The virt-manager/SPICE console goes black after installing the IDD**: this is expected. Windows moves the desktop to the IDD's "Looking Glass" display, and the emulated VGA output is left blank. View the VM with `looking-glass-client` from then on. A healthy client log shows `Using : Looking Glass IDD Driver`, `Using DMA buffer support` and `Using Input: LGMP`. The SPICE console is only a fallback, for when the IDD isn't running.
- **`/dev/kvmfr0` is a regular file** (`ls -l` doesn't start with `c`, or the size is > 0): QEMU started before the module loaded and created it. Stop the VM, `sudo rm /dev/kvmfr0`, `sudo modprobe kvmfr`, and confirm it's a `c` device before starting the VM again.
- **VM won't start, "Permission denied" on `/dev/kvmfr0`**: look for AppArmor denials with `journalctl -k | grep -i apparmor.*kvmfr`, or a missing cgroup ACL with `sudo grep -A6 'BEGIN Looking Glass' /etc/libvirt/qemu.conf`. Restart libvirtd after editing `qemu.conf`.
- **Client can't open the shm device**: the uaccess ACL is missing, so log out and back in, or run `sudo udevadm trigger -s kvmfr`.
- **No modes or a dynamic resolution is refused**: the resolution doesn't fit in 64 MiB, so raise `kvmfr_static_size_mb` and the VM `size` together.
- **IDD logs**: open them from the tray helper; see `doc/idd_diagnostics.rst` upstream for what to collect.
