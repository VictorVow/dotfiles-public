# Waydroid

Waydroid runs a full Android system (LineageOS) inside a Linux container using kernel
namespaces and the Android binder IPC driver. Apps appear as native windows on the KDE
Plasma desktop and have access to GPU acceleration, audio, camera, and clipboard.

---

## Architecture

```
KDE Plasma (Wayland)
  └── waydroid show-full-ui  ─── Android UI window (or individual app windows)
        └── LXC container
              └── LineageOS (Android 13+)
                    ├── /dev/binderfs  ← binder_linux kernel module
                    └── GPU via Mesa passthrough
```

- **`waydroid-container.service`** — root-level systemd service; manages the LXC container lifecycle.
- **`waydroid session`** — user-level session that connects the running container to the display.
- **Images** — stored in `/var/lib/waydroid/images/` (system.img + vendor.img), ~1.5–2 GB.

---

## First-Time Setup

```bash
# 1. Install waydroid + kernel module extras (adds PPA, installs package)
bash 3rd-party-packages/waydroid.sh

# 2. Enable service + load binder_linux module
ansible-playbook ansible.yml --ask-become-pass

# 3. Add waydroid-helper to PATH
hms

# 4. Download LineageOS system + vendor images with MindTheGapps (~1.5 GB)
waydroid init -s LINEAGE -r gapps

# 5. Start session and open Android home screen
waydroid session start && waydroid show-full-ui
```

If `binder_linux` doesn't load after step 2 (e.g. `linux-modules-extra-*` wasn't yet
installed for the running kernel), reboot after step 1 and re-run step 2.

Images land in `/var/lib/waydroid/images/`. To switch variants later (e.g. to vanilla):
```bash
sudo waydroid init -f -s LINEAGE -r vanilla
```

The container starts automatically via `waydroid-container.service`, but the *session*
must be started by the user each time. You can autostart it on login — see
[Autostart](#autostart).

### Vanilla alternative (no Google services)

```bash
waydroid init -s LINEAGE -r vanilla
```

---

## Google Services Setup

The `-r gapps` image ships with Google Play Services and Play Store via MindTheGapps.
To use Play Store you must register the device with Google (one-time).

### Register the device

```bash
# While a session is running, get your Android ID
sudo waydroid-helper --get-android-id
# Outputs a 16-digit number like: 1234567890abcdef
```

1. Visit https://www.google.com/android/uncertified/ in a browser.
2. Sign in with your Google account.
3. Paste the Android ID and click **Register**.
4. Inside Waydroid, open **Settings → Accounts → Add account → Google** and sign in.

Play Store will now show "Device is certified" in its settings.

> **Note:** Google may take up to 15 minutes to propagate the registration.
> If Play Store still shows uncertified, try restarting the Waydroid session.

---

## ARM Translation (libhoudini)

Most Play Store apps are built for ARM/ARM64. Waydroid runs on x86_64, so ARM apps need
a translation layer. `waydroid-helper` (from Nix) installs Intel's libhoudini.

```bash
# Install libhoudini (ARM translation) — patches the system image, requires root
sudo waydroid-helper install libhoudini

# Alternative: libndk (open-source, less compatible than libhoudini)
sudo waydroid-helper install libndk

# After installing, restart the session
waydroid session stop
waydroid session start
```

libhoudini covers ~95% of ARM-only Play Store apps. Without it, many popular apps crash
on launch with "App not installed" or "SIGILL" errors.

---

## App Installation

### From Google Play Store

Sign in with a Google account (requires device registration above), then install apps
normally inside the Play Store UI.

### From Aurora Store (recommended — no Google account needed)

Aurora Store is a Play Store client that uses anonymous tokens. It lets you install and
update Play Store apps without signing in.

```bash
# Download the latest Aurora Store APK from F-Droid (trusted source)
wget https://f-droid.org/repo/com.aurora.store_*.apk -O /tmp/aurora.apk
waydroid app install /tmp/aurora.apk
```

Or install via `adb`:
```bash
adb connect 192.168.x.x  # Waydroid's default IP while session is running
adb install /tmp/aurora.apk
```

**First launch:** Open Aurora Store → tap the person icon → choose **Anonymous** login.
Aurora Store will rotate through anonymous tokens automatically.

### From F-Droid

F-Droid hosts free, open-source Android apps. Install the F-Droid client:

```bash
# Download from the official site
curl -L https://f-droid.org/F-Droid.apk -o /tmp/fdroid.apk
waydroid app install /tmp/fdroid.apk
```

On first launch, let F-Droid update its repository index (~100 MB download).
Notable repos to add in F-Droid → Settings → Repositories:
- **IzzyOnDroid** — https://apt.izzysoft.de/fdroid/repo (wider app selection)

### From Obtainium

Obtainium installs apps directly from their GitHub/GitLab/F-Droid/APKMirror release pages,
bypassing app stores entirely. Useful for apps not on Play Store.

```bash
# Download latest Obtainium APK from GitHub releases
curl -L https://github.com/ImranR98/Obtainium/releases/latest/download/app-release.apk \
    -o /tmp/obtainium.apk
waydroid app install /tmp/obtainium.apk
```

Add apps by URL, e.g. for Signal: paste `https://github.com/signalapp/Signal-Android`
and Obtainium will track releases automatically.

### Sideload any APK

```bash
waydroid app install /path/to/app.apk
```

Or with adb (required for split APKs):
```bash
adb connect 192.168.x.x
adb install /path/to/app.apk
adb install-multiple base.apk split_config.arm64_v8a.apk  # for split APKs
```

---

## Session Management

```bash
# Start session (connects to already-running container service)
waydroid session start

# Open the full Android home screen
waydroid show-full-ui

# Launch a specific app by package name
waydroid app launch com.example.app

# List installed apps
waydroid app list

# Install an APK
waydroid app install /path/to/app.apk

# Stop the session (container keeps running in background)
waydroid session stop

# Check current status
waydroid status
```

### Autostart

To start the Waydroid session automatically at login, add to your KDE autostart
(or as a systemd user unit):

```bash
# ~/.config/autostart/waydroid-session.desktop
[Desktop Entry]
Type=Application
Name=Waydroid Session
Exec=waydroid session start
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
```

Or via `systemctl --user`:
```bash
# Create ~/.config/systemd/user/waydroid-session.service
[Unit]
Description=Waydroid user session
After=graphical-session.target

[Service]
ExecStart=waydroid session start
ExecStop=waydroid session stop
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```
```bash
systemctl --user enable --now waydroid-session.service
```

---

## KDE Plasma / Wayland Integration

### App launcher shortcuts

After installing apps in Waydroid, shortcuts appear automatically in the KDE app
launcher under an "Android" category. These call `waydroid app launch <package>`.

If shortcuts don't appear, refresh with:
```bash
waydroid prop set persist.waydroid.fake_wifi true   # optional, fixes some app checks
```

### Window mode vs full UI

- **Full UI** (`waydroid show-full-ui`) — entire Android home screen in one window, supports all gestures.
- **Window mode** — individual Android apps open as separate KDE windows. Works well for most apps.

To force window mode for all apps:
```bash
waydroid prop set persist.waydroid.multi_windows true
```

### Clipboard

Clipboard sharing between Waydroid and KDE works automatically in recent versions.
If it stops working, restart the session.

### File sharing

Host files are accessible inside Android at `/sdcard/` (which maps to
`~/.local/share/waydroid/data/media/0/`):

```bash
# Copy a file to Android's Downloads
cp ~/Downloads/file.pdf ~/.local/share/waydroid/data/media/0/Download/

# Access Android files from the host
ls ~/.local/share/waydroid/data/media/0/
```

---

## Networking

Waydroid creates a virtual network bridge. While a session is active:
- Waydroid's Android IP: `192.168.x.x`
- Host side: `192.168.x.x` (accessible from Android for LAN services)

For `adb` access:
```bash
adb connect 192.168.x.x
adb devices  # should show "192.168.x.x:5555 device"
```

### nftables

This system uses nftables. The `waydroid-container.service` configures its own nftables
rules at startup. If Android has no internet:
```bash
# Check waydroid nftables rules are present
sudo nft list ruleset | grep waydroid

# If missing, restart the container service
sudo systemctl restart waydroid-container
```

---

## Daily Maintenance

### Updating Android system images

```bash
# Re-initialize to get the latest LineageOS images (destructive — reinstall all apps)
sudo waydroid init -f -s LINEAGE -r gapps
```

Waydroid images don't auto-update. Check https://sourceforge.net/projects/waydroid/files/images/
periodically for new releases, or update apps inside Aurora Store / Play Store normally.

### Checking logs

```bash
# Container service logs
journalctl -u waydroid-container -f

# Session logs
waydroid log

# Android logcat (requires adb connection)
adb logcat
```

### Factory reset

```bash
waydroid session stop
sudo systemctl stop waydroid-container
sudo rm -rf /var/lib/waydroid/data   # wipes app data only
# Or full reset including images:
sudo waydroid init -f -s LINEAGE -r gapps
sudo systemctl start waydroid-container
waydroid session start
```

---

## Troubleshooting

### `binder_linux` module not loaded

```bash
lsmod | grep binder
# If empty:
sudo modprobe binder_linux
# Persist:
echo "binder_linux" | sudo tee /etc/modules-load.d/waydroid.conf
```

If `modprobe` fails with "Module not found":
```bash
# Ensure the extras package is installed for the running kernel
sudo apt install "linux-modules-extra-$(uname -r)"
sudo reboot
```

### Session won't start / "Failed to start session"

```bash
# Check if the container service is running
systemctl status waydroid-container

# Restart it
sudo systemctl restart waydroid-container

# Then start the session again
waydroid session start
```

### Black screen / blank window on Wayland

If `waydroid show-full-ui` opens but shows a black screen on KDE/Wayland:
```bash
# Set the display to use the Wayland socket directly
waydroid prop set persist.waydroid.display_device HWUI

# Or try forcing software rendering (slower but works as a diagnostic)
waydroid prop set persist.waydroid.render_engine swiftshader
waydroid session stop && waydroid session start
```

### Play Store shows "Device not certified"

Follow the [device registration steps](#register-the-device) above. The process must be
repeated if you re-initialize Waydroid images (the Android ID changes).

### ARM app crashes immediately (SIGILL, "App not installed")

Install ARM translation:
```bash
sudo waydroid-helper install libhoudini
waydroid session stop && waydroid session start
```

### `adb connect` fails

Ensure the session is running (`waydroid status`) and try:
```bash
adb kill-server
adb connect 192.168.x.x:5555
```

### App window doesn't appear / stays in background

```bash
# Focus the app by package name
waydroid app launch com.example.app
# Or restart with:
waydroid session stop && waydroid session start && waydroid show-full-ui
```
