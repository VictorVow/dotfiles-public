{ pkgs, lib, ... }:

# Scheduled runs for the agent-transcript secret scrubber (scripts/security/).
# The script is baked into the store with its gitleaks config beside it, so the
# service works even when ~/Projects/installs is dirty or missing.
# Log: journalctl --user -u transcript-scrub.service
let
  scrubScript = pkgs.runCommand "scrub-transcripts" { } ''
    mkdir -p $out
    cp ${../../scripts/security/scrub-transcripts.sh} $out/scrub-transcripts.sh
    cp ${../../scripts/security/transcript-common.sh} $out/transcript-common.sh
    cp ${../../scripts/security/transcript_common.py} $out/transcript_common.py
    cp ${../../scripts/security/gitleaks-scrub.toml} $out/gitleaks-scrub.toml
    chmod +x $out/scrub-transcripts.sh
  '';

  # Apprise endpoint on lord-ubuntu (tailnet). The `matrix-scrub` tag routes
  # to the dedicated "Transcript scrub" room; falls back to nothing if the
  # tag isn't rendered (MATRIX_SCRUB_ROOM unset) — curl still exits 0.
  appriseUrl = "https://apprise.device.example.com/notify/apprise";

  # Posts a one-line summary to Matrix. Reads the scrubber's own journal since
  # invocation for the stats line. $1 = title, $2 = extra body text.
  notifyScript = pkgs.writeShellScript "transcript-scrub-notify" ''
    set -u
    title="$1"; extra="''${2:-}"
    stats=$(${pkgs.systemd}/bin/journalctl --user -u transcript-scrub.service \
      --since "-10min" --no-pager -q \
      | ${pkgs.gnugrep}/bin/grep -E "redacted|forgot|pending|scan error|dirty|review" \
      | ${pkgs.coreutils}/bin/tail -6 || true)
    body="$extra
$stats"
    ${pkgs.curl}/bin/curl -sSf -m 20 -X POST \
      -d "title=$title" \
      --data-urlencode "body=$body" \
      -d "tag=matrix-scrub" \
      "${appriseUrl}" >/dev/null || \
      echo "apprise notify failed" >&2
  '';
in
{
  # Daily incremental scrub: only files/rows newer than the state high-water
  # mark hit gitleaks, so the run is cheap. Runs before cass-nightly (03:00)
  # so forget+re-index lands inside the same nightly window.
  # Success + failure both land in the "Transcript scrub" Matrix room.
  systemd.user.services.transcript-scrub = {
    Unit = {
      Description = "Scrub leaked secrets from agent transcripts";
      OnFailure = [ "transcript-scrub-failed.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${scrubScript}/scrub-transcripts.sh";
      ExecStartPost = "${notifyScript} 'transcript-scrub ok'";
      Environment = [
        "PATH=${
          lib.makeBinPath (
            with pkgs;
            [
              bash
              gitleaks
              python3
              coreutils
              util-linux # flock
              zstd       # zed threads.db blob de/recompression
            ]
          )
        }"
      ];
      Nice = 19;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "30min";
    };
  };

  # Fires only when ExecStart fails (non-zero exit, timeout, kill).
  systemd.user.services.transcript-scrub-failed = {
    Unit.Description = "Notify transcript-scrub failure";
    Service = {
      Type = "oneshot";
      ExecStart = "${notifyScript} 'transcript-scrub FAILED' 'exit non-zero — check journalctl --user -u transcript-scrub'";
    };
  };

  systemd.user.timers.transcript-scrub = {
    Unit.Description = "Daily transcript secret scrub";
    Timer = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
      RandomizedDelaySec = 60;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
