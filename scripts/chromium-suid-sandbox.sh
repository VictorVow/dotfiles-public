#!/usr/bin/env bash
# chromium-suid-sandbox.sh — install the setuid-root SUID sandbox helpers that
# the Nix ungoogled-chromium and google-chrome wrappers expect at
# /run/wrappers/bin.
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
#   google-chrome (nix/modules/packages.nix) hits the exact same problem with
#   its own bundled chrome-sandbox binary, but it ignores CHROME_DEVEL_SANDBOX
#   in release builds (verified — that env var is a locked-down dev-only
#   escape hatch), so unlike ungoogled-chromium it can't be redirected to a
#   fixed path. Instead this bind-mounts a setuid-root copy directly over the
#   read-only Nix store's share/google/chrome/chrome-sandbox path — the one
#   place Chrome will actually look.
#
#   Ubuntu's AppArmor also clamps unprivileged user namespaces
#   (kernel.apparmor_restrict_unprivileged_userns=1), so the modern namespace
#   sandbox is unavailable too. The SUID sandbox is therefore the path that
#   keeps both browsers fully sandboxed here — which is the whole reason this
#   repo runs them from Nix instead of Flatpak (see nix/modules/packages.nix).
#
#   /run is tmpfs and is wiped on every boot, so this runs at boot via the
#   chromium-suid-sandbox.service systemd unit. Re-run it after a browser
#   update (home-manager switch) too: `sudo systemctl restart chromium-suid-sandbox`.
#
# Must run as root (setuid install).
set -euo pipefail

USER_NAME="${SUDO_USER:-boss}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
DEST_DIR="/run/wrappers/bin"

# Copy $1 (a resolved helper binary path) to $2 (the fixed destination path),
# then chown+chmod it setuid-root. Order matters: chown clears the
# setuid/setgid bits, so chmod MUST come last or the helper ends up 0755 and
# the browser aborts ("must be owned by root, mode 4755"). Staged to a temp
# path and atomically moved into place so there is never a window where a
# non-setuid helper is visible.
install_setuid_helper() {
  local helper="$1" dest="$2" label="$3"
  local tmp="$dest.new.$$"
  cp -f "$helper" "$tmp"
  chown root:root "$tmp"
  chmod 4755 "$tmp"
  mv -f "$tmp" "$dest"
  echo "chromium-suid-sandbox: installed setuid helper $dest -> (from $helper) [$label]"
}

install -d -m 0755 "$DEST_DIR"

# ── ungoogled-chromium ───────────────────────────────────────────────────────
CHROMIUM_WRAPPER="$USER_HOME/.nix-profile/bin/chromium"
if [[ -x "$CHROMIUM_WRAPPER" ]]; then
  # The wrapper bakes in the Nix-store path of the sandbox helper; pull it out.
  HELPER="$(grep -oE '/nix/store/[^"]*-sandbox/bin/__chromium-suid-sandbox' "$CHROMIUM_WRAPPER" | tail -1 || true)"
  if [[ -n "$HELPER" && -e "$HELPER" ]]; then
    install_setuid_helper "$HELPER" "$DEST_DIR/__chromium-suid-sandbox" "chromium"
  else
    echo "chromium-suid-sandbox: could not resolve chromium helper from wrapper — skipping." >&2
  fi
else
  echo "chromium-suid-sandbox: no chromium wrapper at $CHROMIUM_WRAPPER — skipping."
fi

# ── google-chrome ────────────────────────────────────────────────────────────
# .google-chrome-stable-wrapped only exists if some earlier revision of this
# script's Nix override double-wrapped the binary; check it first as a
# leftover-safe fallback, but the normal case is the plain wrapper.
CHROME_WRAPPER="$USER_HOME/.nix-profile/bin/google-chrome-stable"
[[ -x "$CHROME_WRAPPER" ]] || CHROME_WRAPPER="$USER_HOME/.nix-profile/bin/.google-chrome-stable-wrapped"
if [[ -x "$CHROME_WRAPPER" ]]; then
  # The wrapper execs the real binary from its Nix store output; chrome-sandbox
  # ships as a sibling file in the same directory.
  CHROME_BIN="$(grep -oE '/nix/store/[^"]*/share/google/chrome/google-chrome' "$CHROME_WRAPPER" | tail -1 || true)"
  CHROME_SANDBOX_TARGET="$(dirname "${CHROME_BIN:-}")/chrome-sandbox"
  if [[ -n "$CHROME_BIN" && -e "$CHROME_SANDBOX_TARGET" ]]; then
    install_setuid_helper "$CHROME_SANDBOX_TARGET" "$DEST_DIR/__google-chrome-suid-sandbox" "google-chrome"

    # Chrome ignores CHROME_DEVEL_SANDBOX and only ever looks at the sibling
    # path next to its own binary, which lives in the read-only Nix store —
    # so the setuid copy has to be made visible AT that exact path via a
    # bind mount, not just installed under /run/wrappers.
    #
    # Unmount any bind mount(s) left over from a previous (now-superseded)
    # google-chrome store path first, so old store paths aren't held open
    # and blocked from GC forever.
    while read -r stale_target; do
      [[ -n "$stale_target" && "$stale_target" != "$CHROME_SANDBOX_TARGET" ]] || continue
      umount "$stale_target" 2>/dev/null || true
      echo "chromium-suid-sandbox: unmounted stale bind mount at $stale_target"
    done < <(findmnt -rn -o TARGET | grep -F '/share/google/chrome/chrome-sandbox' || true)

    if ! mountpoint -q "$CHROME_SANDBOX_TARGET"; then
      mount --bind "$DEST_DIR/__google-chrome-suid-sandbox" "$CHROME_SANDBOX_TARGET"
      echo "chromium-suid-sandbox: bind-mounted setuid helper onto $CHROME_SANDBOX_TARGET"
    fi
  else
    echo "chromium-suid-sandbox: could not resolve google-chrome sandbox helper — skipping." >&2
  fi
else
  echo "chromium-suid-sandbox: no google-chrome wrapper at $CHROME_WRAPPER — skipping."
fi
