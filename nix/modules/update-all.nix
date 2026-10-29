{ hostProfile, ... }:

# Unattended update-all (update.sh). Shared by boss-laptop (daily) and
# lord-ubuntu (every 2 days). update.sh picks the per-host behaviour itself
# (home-manager config = $USER; lord pulls the lock instead of age-pinning).
# apt + the chromium-suid-sandbox restart are NOPASSWD via
# /etc/sudoers.d/update-all on boss (ansible.yml); lord already has NOPASSWD.
# update.sh uses `sudo -n` without a TTY, so a missing rule fails the step
# instead of hanging. The run posts its full output to the Notifications hub
# itself (source update-all-laptop / update-all-homeserver, high priority on failure) — no OnFailure unit.
# Output goes to the journal and ~/.local/state/update-all/update.log.
let
  # flakePath is "$HOME/…/nix"; %h is systemd's spelling of $HOME.
  repo = builtins.replaceStrings [ "$HOME" ] [ "%h" ] (dirOf hostProfile.hms.flakePath);
in
{
  systemd.user.services.update-all = {
    Unit = {
      Description = "Update all package managers (update.sh)";
      Wants = [ "network-online.target" ];
      After = [ "network-online.target" ];
      # The run itself does `home-manager switch`; never let that switch
      # restart/stop this unit mid-run.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${repo}/update.sh";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.update-all = {
    Unit.Description = if hostProfile.isServer then "update-all every 2 days" else "Daily update-all";
    Timer = {
      # Server: odd days of the month (so the 31st and 1st run back to back).
      OnCalendar = if hostProfile.isServer then "*-*-1/2 04:00" else "*-*-* 10:00";
      Persistent = true; # catch up after the machine was off/asleep
      RandomizedDelaySec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
