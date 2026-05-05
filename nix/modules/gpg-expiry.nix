{ pkgs, ... }:

let
  # Scans all GPG secret keys; sends a desktop notification if any expire
  # within THRESHOLD_DAYS. Extend with: gpg --quick-set-expire <fpr> 2y
  gpgExpiryCheck = pkgs.writeShellScript "gpg-expiry-check" ''
    set -euo pipefail

    THRESHOLD_DAYS=30
    NOW=$(date +%s)
    SOON=$(( NOW + THRESHOLD_DAYS * 86400 ))

    # Parse colon-format output: capture sec line's keyid+expiry, then the
    # following uid line's user-id, emit one row per key needing attention.
    flagged=$(${pkgs.gnupg}/bin/gpg --list-secret-keys --with-colons 2>/dev/null \
      | ${pkgs.gawk}/bin/awk -F: -v now="$NOW" -v soon="$SOON" '
          $1=="sec" {
            keyid=$5; expiry=$7; show=0
            if (expiry != "" && expiry+0 < soon) show=1
          }
          show && $1=="uid" {
            days = int((expiry - now) / 86400)
            if (days < 0) status = "EXPIRED " (-days) "d ago"
            else          status = "expires in " days "d"
            printf "• %s (%s): %s\n", keyid, $10, status
            show=0
          }
        ')

    if [ -n "$flagged" ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical -a gpg-expiry \
        "GPG key(s) need attention" \
        "$flagged

Extend all keys by 2y:  gpg-extend-keys
Custom expiry:          gpg-extend-keys 1y
Clear this warning:     systemctl --user start gpg-expiry-check.service"
    fi
  '';
  # Extend every secret key in the keyring by 2 years (primary + all subkeys).
  # Prompts once per key for passphrase. Idempotent — re-running is safe.
  gpgExtendKeys = pkgs.writeShellApplication {
    name = "gpg-extend-keys";
    runtimeInputs = [ pkgs.gnupg pkgs.gawk ];
    text = ''
      EXPIRY="''${1:-2y}"
      # Only primary-key fingerprints (fpr line immediately after sec, not ssb).
      mapfile -t fprs < <(gpg --list-secret-keys --with-colons \
        | awk -F: '$1=="sec"{want=1; next} want && $1=="fpr"{print $10; want=0}')

      if [ ''${#fprs[@]} -eq 0 ]; then
        echo "No secret keys found." >&2
        exit 1
      fi

      for fpr in "''${fprs[@]}"; do
        echo ">>> Extending $fpr by $EXPIRY"
        gpg --quick-set-expire "$fpr" "$EXPIRY" '*'
      done
    '';
  };
in
{
  home.packages = [ gpgExtendKeys ];

  systemd.user.services.gpg-expiry-check = {
    Unit.Description = "Warn when GPG signing keys are near expiry";
    Service = {
      Type = "oneshot";
      ExecStart = "${gpgExpiryCheck}";
    };
  };

  systemd.user.timers.gpg-expiry-check = {
    Unit.Description = "Weekly GPG key expiry check";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
