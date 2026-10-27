{ pkgs, config, ... }:

let
  # Orca's session-history indexer scans ~/.local/share/opencode/opencode*.db but
  # opencode1's DB lives under ~/.opencode1/data/opencode. Hardlinks make it
  # visible (symlinks are rejected by dirent.isFile()); when opencode1
  # checkpoints, SQLite recreates -wal/-shm as fresh inodes, so this re-links
  # them when the names and the real files no longer share an inode.
  orcaOpencode1Links = pkgs.writeShellScript "orca-opencode1-links" ''
    set -eu
    src="${config.home.homeDirectory}/.opencode1/data/opencode"
    dst="${config.home.homeDirectory}/.local/share/opencode"
    for f in opencode.db opencode.db-wal opencode.db-shm; do
      s="$src/$f"
      d="$dst/opencode-1''${f#opencode}"
      [ -f "$s" ] || continue
      if [ ! -f "$d" ] || [ "$(stat -c %i "$s")" != "$(stat -c %i "$d")" ]; then
        ln -f "$s" "$d"
      fi
    done
  '';
  # OnFailure handler for update-all. update.sh exits 1 when any step failed
  # (and also on a crash), so pull the "Some steps failed: …" summary line out
  # of that run's journal; fall back to a generic message for a crash.
  updateAllFailedNotify = pkgs.writeShellScript "update-all-failed-notify" ''
    failed=$(/usr/bin/journalctl --user -u update-all.service --invocation=0 -o cat \
      | ${pkgs.gnugrep}/bin/grep -o 'Some steps failed: .*' \
      | ${pkgs.gnused}/bin/sed 's/\x1b\[[0-9;]*m//g' | ${pkgs.coreutils}/bin/tail -1)
    ${pkgs.libnotify}/bin/notify-send -u critical -a update-all "update-all failed" \
      "''${failed:-update.sh exited with an error}

journalctl --user -u update-all"
  '';
in
{
  systemd.user.services.ollama = {
    Unit = {
      Description = "Ollama AI model server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.ollama-vulkan}/bin/ollama serve";
      Restart = "always";
      RestartSec = "3";
      Environment = [
        "OLLAMA_HOST=127.0.0.1:11434"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.jackett = {
    Unit = {
      Description = "Jackett torrent indexer proxy";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.jackett}/bin/jackett --NoRestart --NoUpdates";
      Restart = "always";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.orca-opencode1-links = {
    Unit.Description = "Re-link opencode1 session DB into Orca's indexed directory";
    Service = {
      Type = "oneshot";
      ExecStart = "${orcaOpencode1Links}";
    };
  };
  systemd.user.timers.orca-opencode1-links = {
    Unit.Description = "opencode1 DB hardlink refresh timer";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # RustDesk's --server spawns a `rustdesk --tray` icon once per (re)start;
  # Tray-Launcher owns GUI access instead. hide-tray is a builtin option only
  # loadable via a cryptographically signed custom.txt, so we pkill the
  # process on a timer. pkill exits 1 when nothing matches — that's fine.
  systemd.user.services.rustdesk-tray-killer = {
    Unit = {
      Description = "Kill rustdesk --tray (Tray-Launcher takes over GUI access)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/usr/bin/pkill -f '^/usr/share/rustdesk/rustdesk --tray'";
      SuccessExitStatus = "0 1";
    };
  };
  systemd.user.timers.rustdesk-tray-killer = {
    Unit = {
      Description = "Kill rustdesk --tray periodically (it respawns from --server)";
      After = [ "graphical-session.target" ];
    };
    Timer = {
      OnBootSec = "30";
      OnUnitActiveSec = "60";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Daily unattended update-all. apt + the chromium-suid-sandbox restart are
  # NOPASSWD via /etc/sudoers.d/update-all (ansible.yml); update.sh uses
  # `sudo -n` without a TTY, so a missing rule fails the step instead of
  # hanging. update.sh exits 1 if any step failed, which triggers the
  # update-all-failed notification. Output goes to the journal
  # and ~/.local/state/update-all/update.log.
  systemd.user.services.update-all = {
    Unit = {
      Description = "Update all package managers (update.sh)";
      Wants = [ "network-online.target" ];
      After = [ "network-online.target" ];
      OnFailure = [ "update-all-failed.service" ];
      # The run itself does `home-manager switch`; never let that switch
      # restart/stop this unit mid-run.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/Projects/installs/update.sh";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.services.update-all-failed = {
    Unit.Description = "Notify that update-all failed";
    Service = {
      Type = "oneshot";
      ExecStart = "${updateAllFailedNotify}";
    };
  };
  systemd.user.timers.update-all = {
    Unit.Description = "Daily update-all";
    Timer = {
      OnCalendar = "*-*-* 10:00";
      Persistent = true; # catch up after the laptop was off/asleep at 10:00
      RandomizedDelaySec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  home.packages = [ pkgs.ollama-vulkan ];

}
