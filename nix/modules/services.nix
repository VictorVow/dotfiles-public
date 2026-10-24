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

  # Daily unattended update-all. apt + the chromium-suid-sandbox restart are
  # NOPASSWD via /etc/sudoers.d/update-all (ansible.yml); update.sh uses
  # `sudo -n` without a TTY, so a missing rule fails the step instead of
  # hanging. Failed steps raise a notification from update.sh itself; a crash
  # of the whole script triggers update-all-failed. Output goes to the journal
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
    Unit.Description = "Notify that update-all crashed";
    Service = {
      Type = "oneshot";
      ExecStart = ''${pkgs.libnotify}/bin/notify-send -u critical -a update-all "update-all crashed" "journalctl --user -u update-all"'';
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

  # Weekly Nix GC — the only GC (update.sh no longer runs one). Only expires
  # this user's profile generations, but the collection itself frees anything
  # unreferenced.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
    persistent = true;
    randomizedDelaySec = "1h";
  };

  home.packages = [ pkgs.ollama-vulkan ];

}
