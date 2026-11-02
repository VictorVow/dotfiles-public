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

  # magpie gateway — serves every signed-in subscription account (Devin, …) as
  # OpenAI/Anthropic/Responses APIs on 127.0.0.1:3425 so non-OpenCode agents
  # (Hermes, whose config.yaml magpie rewrites to provider magpie) can use them.
  # Without a running magpie process nothing answers :3425, so the agents it
  # wired break — keep it up like ollama. `magpie serve` is the headless mode
  # (tui/web also serve while open). Providers/sign-ins live in ~/.config/magpie.
  systemd.user.services.magpie = {
    Unit = {
      Description = "magpie gateway (shared AI subscription accounts on :3425)";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${config.home.profileDirectory}/bin/magpie serve";
      Restart = "always";
      RestartSec = "5";
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

  # Suppress RustDesk's own tray icon — Tray-Launcher owns GUI access instead.
  #
  # Why this exists:
  # - `rustdesk --server` (user-level, spawned by the root rustdesk.service)
  #   unconditionally runs `pkill -f 'rustdesk --tray'` then `run_me --tray`
  #   at every start — src/core_main.rs, the `--server` arm in rustdesk 1.5.0.
  #   There is no user-facing off switch for this.
  # - `hide-tray` IS a real option (base::config::keys::OPTION_HIDE_TRAY,
  #   checked in src/tray.rs::start_tray()), but it's a *builtin* setting.
  #   Builtin settings are only populated from `custom.txt` next to the exe,
  #   which must be ed25519-signed against RustDesk's hardcoded public key
  #   (src/common.rs::read_custom_client) — unsigned configs are dropped.
  #   Adding it to ~/.config/rustdesk/RustDesk2.toml does nothing (that file
  #   only feeds user options, and gets rewritten anyway).
  # - --server restarts periodically (should_start_server watchdog, roughly
  #   hourly), and each restart spawns a fresh --tray, so a one-shot kill at
  #   login is not enough — this timer re-kills every 60s.
  # - Killing --tray does not affect remote sessions: it's purely the
  #   StatusNotifier icon + "Open"/"Stop service" menu. The GUI window is
  #   opened separately by Tray-Launcher.
  # Why /usr/bin/pkill -f with an anchored full path: `pkill -f 'rustdesk
  # --tray'` self-matches the invoking shell's own cmdline; the anchored
  # pattern can't. pkill exits 1 when nothing matches — expected between
  # spawns — hence SuccessExitStatus.
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

  home.packages = [ pkgs.ollama-vulkan ];

}
