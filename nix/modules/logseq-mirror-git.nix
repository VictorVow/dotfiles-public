{ pkgs, config, ... }:

# Hourly git snapshot of the logseq-apex Markdown mirror (Logseq Settings >
# Features > Markdown mirror writes one .md per page/journal on every DB change).
# Gives readable `git log -p` / `git diff` history of a DB graph whose sqlite
# file is opaque blobs. The repo lives inside mirror/markdown only, so the
# 33 GB of db/backups/assets beside it are never touched.
let
  dir = "${config.home.homeDirectory}/logseq/graphs/logseq-apex/mirror/markdown";
  git = "${pkgs.git}/bin/git";
  snapshot = pkgs.writeShellScript "logseq-mirror-git" ''
    set -eu
    cd ${dir}
    [ -d .git ] || ${git} init -q
    ${git} add -A
    ${git} diff --cached --quiet || ${git} -c user.name=logseq-mirror -c user.email=logseq-mirror@localhost commit -qm "snapshot $(date -Is)"
  '';
in
{
  systemd.user.services.logseq-mirror-git = {
    Unit.Description = "Git snapshot of the logseq-apex Markdown mirror";
    Service = {
      Type = "oneshot";
      ExecStart = "${snapshot}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.logseq-mirror-git = {
    Unit.Description = "Hourly git snapshot of the logseq-apex Markdown mirror";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
