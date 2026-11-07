{ config, pkgs, lib, hostProfile, ... }:

# Background index refresh for cass (coding-agent session search), used by the
# search-agent-history skill.
# Declarative equivalent of `cass schedule install` (units mirrored from its --dry-run, cass
# 0.10.0), with two differences: ExecStart uses the stable brew bin symlink instead of the
# versioned Cellar path, so `brew upgrade` doesn't break it; and output goes to the journal
# (`journalctl --user -u cass-incremental`) instead of an appended log file.
# Don't also run `cass schedule install`: it would write duplicate units under ~/.config/systemd.
#
# Binary path: desktop uses brew (/home/linuxbrew/.linuxbrew/bin/cass via
# Brewfile). Server (lord-ubuntu) skips brew — the upstream tap's cass.rb
# doesn't ship a generic Linux URL so `brew bundle` fails on Ubuntu 26.04 —
# and instead the release tarball is fetched once by the activation script
# below into ~/.local/bin/cass. Update by bumping cassVersion + re-running hms.
let
  cassVersion = "0.10.0";  # bump alongside the desktop's `brew upgrade cass`
  cass = if hostProfile.isServer
    then "${config.home.homeDirectory}/.local/bin/cass"
    else "/home/linuxbrew/.linuxbrew/bin/cass";
  dataDir = "${config.home.homeDirectory}/.local/share/coding-agent-search";

  # Background priority as cass sets it: only runs when the CPU/disk is otherwise idle.
  # cass also skips a run itself under severe load (/proc/loadavg + PSI).
  mkService = description: job: timeout: {
    Unit = {
      Description = description;
      Documentation = "https://github.com/Dicklesworthstone/coding_agent_session_search";
      # Oneshot with a long timeout: a restart on hms would kill a mid-write index run
      # and block the switch until the new run finishes. Apply from the next fire instead.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${cass} --color=never schedule run --job ${job} --data-dir ${dataDir} --json";
      Environment = [ "CASS_INDEX_NO_PROGRESS_EVENTS=1" ];
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
      # Cap total CPU at ~1/4 of the machine (16 cores); the embedder spawns enough
      # internal threads to saturate all cores otherwise. Work just takes longer.
      CPUQuota = "25%";
      TimeoutStartSec = timeout;
    };
  };
in
{
  # Server-only: fetch the upstream release tarball once and drop the binary
  # at ~/.local/bin/cass. Runs only when the binary is missing or the version
  # stamp doesn't match — safe to re-run.
  home.activation.cassInstall = lib.mkIf hostProfile.isServer (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    stamp="$HOME/.local/share/cass-version"
    bin="$HOME/.local/bin/cass"
    # NOTE: activation blocks are sourced, not run in a subshell — `exit` would
    # terminate the whole `activate` script and skip later steps. Use `if/else`
    # or `return` inside a function instead.
    if ! { [ -x "$bin" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "${cassVersion}" ]; }; then
      url="https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz"
      tmp="$(mktemp -d)"
      if ${pkgs.curl}/bin/curl -sSfL "$url" -o "$tmp/cass.tar.gz"; then
        ${pkgs.gnutar}/bin/tar --use-compress-program ${pkgs.gzip}/bin/gzip -xf "$tmp/cass.tar.gz" -C "$tmp"
        install -d -m 755 "$HOME/.local/bin"
        install -m 755 "$tmp/cass" "$bin"
        mkdir -p "$(dirname "$stamp")"
        printf '%s' "${cassVersion}" > "$stamp"
        echo "cass ${cassVersion} installed to $bin"
      else
        echo "WARNING: cass download failed — timers will no-op until ~/.local/bin/cass exists" >&2
      fi
      rm -rf "$tmp"
    fi
  '');

  # Incremental: new/changed sessions every 15 min (indexes lexically; vectors catch up nightly).
  systemd.user.services.cass-incremental = mkService "cass incremental index refresh" "incremental" "30min";
  systemd.user.timers.cass-incremental = {
    Unit.Description = "cass incremental index timer";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Persistent = true;
      RandomizedDelaySec = 60;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Nightly: full source census + conditional lexical rebuild + bounded MiniLM semantic
  # backfill. Persistent = runs at next boot/login if the laptop was off at 03:00.
  systemd.user.services.cass-nightly = mkService "cass nightly full index + semantic backfill" "nightly" "6h";
  systemd.user.timers.cass-nightly = {
    Unit.Description = "cass nightly index timer";
    Timer = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = 60;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Weekly raw-mirror prune: the mirror snapshots whole source files every run, and
  # SQLite session DBs (opencode.db) churn ~500 MB of unique blobs per capture —
  # unbounded this grew to 26 GB within weeks. Keep the newest 2 captures per
  # source file plus anything <1h old; reclaim the rest.
  systemd.user.services.cass-mirror-prune = {
    Unit = {
      Description = "cass raw-mirror retention prune";
      Documentation = "https://github.com/Dicklesworthstone/coding_agent_session_search";
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${cass} --color=never mirror prune --keep-latest 2 --safety-hold-down 1h --apply --data-dir ${dataDir} --json";
      Environment = [ "CASS_INDEX_NO_PROGRESS_EVENTS=1" ];
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
      CPUQuota = "25%";
      TimeoutStartSec = "30min";
    };
  };
  systemd.user.timers.cass-mirror-prune = {
    Unit.Description = "cass raw-mirror prune timer";
    Timer = {
      OnCalendar = "Sun *-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = 60;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
