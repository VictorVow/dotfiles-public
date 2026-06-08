#!/usr/bin/env bash
# chromium-suid-sandbox.sh — install the setuid-root SUID sandbox helper that
# the Nix ungoogled-chromium wrapper expects at /run/wrappers/bin.
#
# Why this exists:
#   On NixOS, `security.chromiumSuidSandbox.enable` creates a setuid-root copy
#   of Chromium's SUID sandbox helper at /run/wrappers/bin/__chromium-suid-sandbox.
#   The Nix chromium wrapper prefers exactly that path. On a non-NixOS host
#   (Kubuntu + Nix) nothing creates it, so the wrapper falls back to the helper
#   inside the read-only Nix store (which cannot be setuid root) and Chromium
#   aborts: "The SUID sandbox helper binary was found, but is not configured
#   correctly ... is owned by root and has mode 4755".
#
#   Ubuntu's AppArmor also clamps unprivileged user namespaces
#   (kernel.apparmor_restrict_unprivileged_userns=1), so the modern namespace
#   sandbox is unavailable too. The SUID sandbox is therefore the path that
#   keeps Chromium fully sandboxed here — which is the whole reason this repo
#   runs Chromium from Nix instead of Flatpak (see nix/modules/packages.nix).
#
#   /run is tmpfs and is wiped on every boot, so this runs at boot via the
#   chromium-suid-sandbox.service systemd unit. Re-run it after a Chromium
#   update (home-manager switch) too: `sudo systemctl restart chromium-suid-sandbox`.
#
# Must run as root (setuid install).
set -euo pipefail

USER_NAME="${SUDO_USER:-boss}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
WRAPPER="$USER_HOME/.nix-profile/bin/chromium"
DEST_DIR="/run/wrappers/bin"
DEST="$DEST_DIR/__chromium-suid-sandbox"

if [[ ! -x "$WRAPPER" ]]; then
  echo "chromium-suid-sandbox: no chromium wrapper at $WRAPPER — nothing to do."
  exit 0
fi

# The wrapper bakes in the Nix-store path of the sandbox helper; pull it out.
HELPER="$(grep -oE '/nix/store/[^"]*-sandbox/bin/__chromium-suid-sandbox' "$WRAPPER" | tail -1 || true)"

if [[ -z "$HELPER" || ! -e "$HELPER" ]]; then
  echo "chromium-suid-sandbox: could not resolve helper from wrapper — nothing to do." >&2
  exit 0
fi

install -d -m 0755 "$DEST_DIR"

# Copy, set ownership, THEN set the setuid mode — in that order.
# chown clears the setuid/setgid bits, so the chmod MUST come last or the
# helper ends up 0755 and Chromium aborts ("must be owned by root, mode 4755").
# Stage to a temp path and atomically move into place so there is never a
# window where a non-setuid helper is visible.
TMP="$DEST.new.$$"
cp -f "$HELPER" "$TMP"
chown root:root "$TMP"
chmod 4755 "$TMP"
mv -f "$TMP" "$DEST"
echo "chromium-suid-sandbox: installed setuid helper $DEST -> (from $HELPER)"
