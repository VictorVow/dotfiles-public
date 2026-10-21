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
