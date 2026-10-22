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
    if [ -x "$bin" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "${cassVersion}" ]; then
      exit 0
    fi
    url="https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    ${pkgs.curl}/bin/curl -sSfL "$url" -o "$tmp/cass.tar.gz" || {
      echo "WARNING: cass download failed — timers will no-op until ~/.local/bin/cass exists" >&2
      exit 0
    }
    ${pkgs.gnutar}/bin/tar -xzf "$tmp/cass.tar.gz" -C "$tmp"
    install -d -m 755 "$HOME/.local/bin"
    install -m 755 "$tmp/cass" "$bin"
    mkdir -p "$(dirname "$stamp")"
    printf '%s' "${cassVersion}" > "$stamp"
    echo "cass ${cassVersion} installed to $bin"
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
}
