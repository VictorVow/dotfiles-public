{
  pkgs,
  lib,
  hostProfile,
  ...
}:

# Firefox Desktop Tabs producer: pushes the live Sidebery tree of the VERTEX
# profile to the self-hosted Desktop Tabs server (lord-ubuntu), and drains
# queued remote-close commands back to the FF Tab Closer native host.
#
# Runs as a systemd USER timer every 30 s on the desktop. The read side is
# ff-live-sidebery-tree.py (sessionstore + Sidebery storage.local — the real
# tree: panelId/parentId/folded/customTitle + panel names); the write side is
# ff-close-tabs.py (native host -> live tab close by URL, incl. discarded).
# ff-push-tree.py hash-skips the PUT when nothing changed, so the 30 s tick
# only drains close commands while idle.
#
# Secrets: TABS_SERVER/TABS_TOKEN come from an EnvironmentFile at
# ~/.config/firefox-desktop-tabs/env (gitignored, create once):
#   TABS_SERVER=https://firefox-desktop-tabs.device.example.com
#   TABS_TOKEN=<same bearer token as the server's .env>
let
  scripts = ../dotfiles/agent-skills/firefox-live-debug/scripts;
  push = "${scripts}/ff-push-tree.py";
in
{
  # Desktop only — the server pulls nothing and has no Sidebery to read.
  config = lib.mkIf (!hostProfile.isServer) {

    systemd.user.services.firefox-desktop-tabs = {
      Unit = {
        Description = "Push Sidebery tab tree to Desktop Tabs server + drain close commands";
        # Don't block a hms switch on a mid-run push.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${push}";
        EnvironmentFile = "-%E/firefox-desktop-tabs/env"; # '-' = optional
        Environment = [ "TABS_PROFILE=%h/.mozilla/firefox/VERTEX" ];
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.firefox-desktop-tabs = {
      Unit.Description = "Sidebery tree push timer (30 s)";
      Timer = {
        OnBootSec = "45s"; # let Firefox + the native host come up first
        # Backstop only — the path unit below does the real work on each
        # sessionstore rewrite; this just catches drift + drains commands.
        OnUnitActiveSec = "60s";
        Persistent = false; # live tree — pointless to catch up after off
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # Also fire the instant Firefox rewrites the session backup, so a new /
    # closed tab syncs within its ~15 s flush cadence instead of up to 30 s.
    systemd.user.paths.firefox-desktop-tabs = {
      Unit.Description = "Push on sessionstore rewrite";
      Path = {
        PathChanged = "%h/.mozilla/firefox/VERTEX/sessionstore-backups/recovery.jsonlz4";
        Unit = "firefox-desktop-tabs.service";
      };
      Install.WantedBy = [ "paths.target" ];
    };
  };
}
