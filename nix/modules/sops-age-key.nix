{ pkgs, lib, hostProfile, ... }:

# The sops-nix age identity is NOT stored as a plaintext file at a persistent
# path. It lives in the Secret Service keyring (KWallet via ksecretd, see
# modules/desktop.nix) under the lookup attributes:
#
#   service = sops-age
#   key     = identity
#
# At login this oneshot service materialises it into
# $XDG_RUNTIME_DIR/sops-age/key (tmpfs, 0400, dies on reboot/logout) so
# sops-nix.service — ordered After this unit — can decrypt nix/secrets/*.yaml.
#
# Why: a static ~/.config/sops/age/keys.txt is readable by any process running
# as this uid (incl. AI agents with file-read access); one read decrypts the
# whole secrets store. The keyring adds a layer the file didn't have.
#
# One-time setup (manual): store the identity once, then delete keys.txt:
#   secret-tool store --label="sops age identity" service sops-age key identity \
#     < ~/.config/sops/age/keys.txt
#   shred -u ~/.config/sops/age/keys.txt
#
# Failure mode: wallet locked / no D-Bus session (e.g. `hms` over ssh before
# graphical login) -> this unit fails and sops-nix fails with it. Unlock/login,
# then `systemctl --user restart sops-age-key sops-nix`.
#
# Interactive `sops` (sops -d, sops nix/secrets/*.yaml) does NOT read this file
# — it gets SOPS_AGE_KEY from the `sops()` shell function in shell.nix, which
# queries the keyring directly.
#
# The uid is baked in because sops.age.keyFile lands in the sops-nix manifest
# at eval time — systemd specifiers like %t never get expanded, and HM exposes
# no home.uid option. 1000 is this machine's first (and only) regular user;
# shell.nix derives XDG_RUNTIME_DIR the same way at runtime.
let
  runtimeDir = "/run/user/1000";
  keyPath = "${runtimeDir}/sops-age/key";
in
lib.mkMerge [
  # ── Desktop: Secret Service → tmpfs at login ───────────────────────────────
  (lib.mkIf (!hostProfile.isServer) {
    # Single source of truth for the key path — rclone.nix and ai-secrets.nix
    # both reference this. sops-nix reads the file at ExecStart, by which time
    # the service below has written it.
    sops.age.keyFile = keyPath;

    systemd.user.services.sops-age-key = {
      Unit = {
        Description = "Materialise sops age identity from Secret Service";
        Before = [ "sops-nix.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Write to a temp file then mv over: on re-runs `key` is already 0400,
        # which a plain `>` redirect can't open for writing.
        ExecStart        = pkgs.writeShellScript "sops-age-key-materialise" ''
          set -euo pipefail
          d="${runtimeDir}/sops-age"
          install -d -m 700 "$d"
          tmp="$(mktemp -p "$d" key.XXXXXX)"
          ${pkgs.libsecret}/bin/secret-tool lookup service sops-age key identity > "$tmp"
          chmod 400 "$tmp"
          mv -f "$tmp" "$d/key"
        '';
      };
      Install.WantedBy = [ "default.target" ];
    };
  })

  # ── Server (lord-ubuntu): no graphical session, no Secret Service ─────────
  # The age identity lives at ~/.config/sops/age/keys.txt (0600, manually
  # provisioned once) — the tradeoff the desktop's Secret-Service indirection
  # exists to avoid. The agent secret-guard rules (ai-agents-server.nix) deny
  # reads of ~/.config/sops/** so the exposure is bounded.
  (lib.mkIf hostProfile.isServer {
    sops.age.keyFile = "/home/lord/.config/sops/age/keys.txt";

    # Ensure the dir exists with right perms; the key file itself is placed
    # out-of-band (copy the private key over once, or generate a dedicated
    # lord keypair and add its public key to .sops.yaml).
    home.activation.sopsAgeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD install -d -m 700 "$HOME/.config/sops/age"
      if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
        echo "WARNING: ~/.config/sops/age/keys.txt missing — sops decryption will fail." >&2
        echo "  Generate a dedicated keypair on lord-ubuntu:" >&2
        echo "    age-keygen -o ~/.config/sops/age/keys.txt" >&2
        echo "  then add the public key to .sops.yaml and run 'sops updatekeys nix/secrets/*.yaml'." >&2
      fi
    '';
  })
]
