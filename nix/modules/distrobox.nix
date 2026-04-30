{ config, pkgs, lib, ... }:

# Declarative Distrobox container definitions.
#
# One container is managed here:
#   1. "fedora" — fedora:latest — Trivalent browser (hardened Chromium) from secureblue repo
#
# Containers are created and initialised via Home Manager activation scripts.
# `distrobox create` is idempotent — it is safe to re-run if the container
# already exists. Package installation uses a sentinel file to avoid
# reinstalling packages on every `home-manager switch`.
#
# Package installs run via `podman exec --user root` to bypass the nosuid
# restriction on container overlay filesystems (which prevents sudo from
# working in non-interactive activation hook contexts).
#
# To enter a container interactively:
#   distrobox enter fedora
#
# To run a one-off command in a container:
#   distrobox enter fedora   -- ls
#
# To re-run package initialisation:
#   rm ~/.local/share/distrobox-hm-init/fedora-initialized
{
  home.activation.distroboxContainers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DISTROBOX="${pkgs.distrobox}/bin/distrobox"
      PODMAN="${pkgs.podman}/bin/podman"

      # Activation runs with a stripped PATH; add required tools.
      export PATH="${pkgs.podman}/bin:${pkgs.crun}/bin:${pkgs.passt}/bin:${pkgs.gawk}/bin:${pkgs.util-linux}/bin:$PATH"

      # Rootless podman needs XDG_RUNTIME_DIR to locate the user's containers.
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

      SENTINEL_DIR="$HOME/.local/share/distrobox-hm-init"
      $DRY_RUN_CMD mkdir -p "$SENTINEL_DIR"

      # ── Container 1: fedora (fedora:latest) ─────────────────────────────────
      # Purpose: Trivalent browser — a hardened, security-focused Chromium
      # browser from the secureblue project.

      $DRY_RUN_CMD "$DISTROBOX" create \
        --name fedora \
        --image fedora:latest \
        --yes \
        --no-entry \
        >/dev/null 2>&1 || true

      $DRY_RUN_CMD "$PODMAN" start fedora 2>/dev/null || true

      # Install Trivalent on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/fedora-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/fedora-initialized" ]; then
        echo "Initialising 'fedora' container packages (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root fedora bash -c '
          rpm --import https://repo.secureblue.dev/secureblue.gpg && \
          curl -o /etc/yum.repos.d/secureblue.repo \
            https://repo.secureblue.dev/secureblue.repo && \
          dnf install -y --quiet \
            trivalent
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/fedora-initialized"

          # Export Trivalent to the host desktop.
          DISTROBOX_EXPORT="${pkgs.distrobox}/bin/distrobox-export"
          $DRY_RUN_CMD "$DISTROBOX_EXPORT" --app trivalent --container fedora 2>/dev/null || true
        else
          echo "WARNING: 'fedora' container package install failed; will retry next switch."
        fi
      fi
    '';
}
