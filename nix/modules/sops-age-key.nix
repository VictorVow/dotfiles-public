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
  # The age identity is a systemd-creds-encrypted blob bound to the host's
  # TPM2: ~/.config/sops/age/keys.txt.cred, produced once by
  #   systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs= \
  #     ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.cred
  #   shred -u ~/.config/sops/age/keys.txt
  # (--tpm2-pcrs= empty = bound to the TPM but not to boot PCRs, so kernel
  # and initrd updates don't break decryption.)
  #
  # LoadCredentialEncrypted decrypts the blob into the service's private
  # credentials dir ($CREDENTIALS_DIRECTORY, tmpfs, only this unit can see
  # it) at ExecStart; sops-nix reads it via SOPS_AGE_KEY_FILE. The plaintext
  # never touches disk and isn't readable by any other process or unit —
  # the server-side equivalent of desktop's Secret-Service indirection.
  (lib.mkIf hostProfile.isServer {
    # sops-install-secrets reads the age key path from its baked-in manifest
    # (ageKeyFile), NOT from SOPS_AGE_KEY_FILE env — so we point keyFile at
    # a stable path under $XDG_RUNTIME_DIR that a tiny ExecStartPre fills
    # from the decrypted systemd credential each run. Same convention as
    # the desktop branch (tmpfs, dies at logout) but the source is a TPM-
    # wrapped blob instead of Secret Service.
    sops.age.keyFile = keyPath;

    systemd.user.services.sops-nix = {
      Service = {
        # systemd-creds decrypts keys.txt.cred into the unit's private
        # $CREDENTIALS_DIRECTORY (tmpfs, only this unit can see it).
        LoadCredentialEncrypted = "age-key:%h/.config/sops/age/keys.txt.cred";
        # Copy the decrypted credential to the path sops-install-secrets is
        # baked to read. %d expands to $CREDENTIALS_DIRECTORY; %t is
        # $XDG_RUNTIME_DIR (/run/user/1000).
        ExecStartPre = "${pkgs.writeShellScript "sops-age-key-copy" ''
          set -euo pipefail
          install -d -m 700 %t/sops-age
          install -m 400 %d/age-key %t/sops-age/key
        ''}";
      };
    };

    # Reminder if the .cred isn't provisioned yet — sops-nix will fail with
    # "Failed to set up credentials" otherwise, which is less obvious.
    home.activation.sopsAgeCredCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD install -d -m 700 "$HOME/.config/sops/age"
      if [ ! -f "$HOME/.config/sops/age/keys.txt.cred" ]; then
        echo "WARNING: ~/.config/sops/age/keys.txt.cred missing — sops-nix will fail." >&2
        echo "  Generate a dedicated keypair + TPM-wrap it:" >&2
        echo "    age-keygen -o ~/.config/sops/age/keys.txt" >&2
        echo "    systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs= \\" >&2
        echo "      ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.cred" >&2
        echo "    shred -u ~/.config/sops/age/keys.txt" >&2
        echo "  then add the public key to .sops.yaml and 'sops updatekeys nix/secrets/ai.yaml'." >&2
      fi
    '';
  })
]
