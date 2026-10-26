{ pkgs, ... }:

# Weekly store/image cleanup — the only Nix GC (update.sh no longer runs one)
# plus a Docker prune. Shared by boss-laptop and lord-ubuntu.
#
# Nix GC only expires this user's profile generations, but the collection
# itself frees anything unreferenced (nix-direnv devShell GC roots are
# protected). Docker prune removes only *unused* resources older than 30d —
# stopped containers, dangling+unreferenced images, unused networks, build
# cache — so running containers and the images they use are never touched.
# Prune is non-fatal so a Docker outage can't fail the Nix GC.
let
  weeklyCleanup = pkgs.writeShellScript "weekly-cleanup" ''
    set -eu
    ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 30d
    /usr/bin/docker system prune -af --filter "until=720h" || true
  '';
in
{
  systemd.user.services.weekly-cleanup = {
    Unit.Description = "Nix garbage collection + Docker prune";
    Service = {
      Type = "oneshot";
      ExecStart = "${weeklyCleanup}";
      Nice = 10;
      IOSchedulingClass = "idle";
      # A restart on hms would kill a mid-run GC; apply from the next fire.
      X-SwitchMethod = "keep-old";
    };
  };
  systemd.user.timers.weekly-cleanup = {
    Unit.Description = "Weekly Nix GC + Docker prune";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true; # catch up if the machine was off/asleep
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
