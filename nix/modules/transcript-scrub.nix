{ pkgs, lib, ... }:

# Scheduled runs for the agent-transcript secret scrubber (scripts/security/).
# The script is baked into the store with its gitleaks config beside it, so the
# service works even when ~/Projects/installs is dirty or missing.
# Log: journalctl --user -u transcript-scrub.service
let
  scrubScript = pkgs.runCommand "scrub-transcripts" { } ''
    mkdir -p $out
    cp ${../../scripts/security/scrub-transcripts.sh} $out/scrub-transcripts.sh
    cp ${../../scripts/security/gitleaks-scrub.toml} $out/gitleaks-scrub.toml
    chmod +x $out/scrub-transcripts.sh
  '';
in
{
  # Daily incremental scrub: only files/rows newer than the state high-water
  # mark hit gitleaks, so the run is cheap. Runs before cass-nightly (03:00)
  # so forget+re-index lands inside the same nightly window.
  systemd.user.services.transcript-scrub = {
    Unit.Description = "Scrub leaked secrets from agent transcripts";
    Service = {
      Type = "oneshot";
      ExecStart = "${scrubScript}/scrub-transcripts.sh";
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
            ]
          )
        }"
      ];
      Nice = 19;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "30min";
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
