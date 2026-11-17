# Home Manager configuration for droid (Pixel 8 AVF "Linux Terminal" Debian
# VM, aarch64-linux, user `droid`). Minimal headless set — the VM only runs
# while the Terminal app is open, so no scheduled agent indexers or updaters.
{ lib, ... }:
{
  home.username = "droid";
  home.homeDirectory = "/home/droid";

  # Match the other hosts' stateVersion — determines HM release compat,
  # unrelated to when the config was created.
  home.stateVersion = "24.11";

  nixpkgs.config.allowUnfree = true;

  imports = [
    ./modules/packages-droid.nix # minimal headless package set (adb, tailscale CLI, LLM CLIs)
    ./modules/shell-apps.nix # programs.* — git/tmux/starship/htop/gh/direnv/ssh (all headless-safe)
    ./modules/ai-agents-server.nix # Claude Code + OpenCode 2 + magpie plugins (no browser MCPs)
    ./modules/shell-server.nix # bash env, hms/nsh/nr, trimmed of desktop bits
    ./modules/ai-secrets-droid.nix # freellmapi/refuseless keys only → env for the opencode wrappers
    ./modules/weekly-cleanup.nix # weekly Nix GC (docker prune auto-skips — no docker here)
    ./modules/agent-skills.nix # ~/.claude/skills — desktop-only skills filtered via hostProfile.isServer
  ];

  # Non-NixOS Linux (Debian 12 AVF guest).
  targets.genericLinux.enable = true;

  xdg.enable = true;
  home.preferXdgDirectories = true;

  # sops age key: NOT sops-age-key.nix — that module's server branch expects a
  # systemd-creds host-key-wrapped credential (lord-ubuntu). On this disposable
  # VM plaintext keys.txt is fine. sops-nix requires an explicit keyFile on
  # genericLinux (no SSH host keys to fall back to). Generate it once on the
  # VM (age-keygen -o ~/.config/sops/age/keys.txt) and add the pubkey to
  # .sops.yaml's &droid entry — see docs/system/bootstrap-new-host.md.
  sops.age.keyFile = "/home/droid/.config/sops/age/keys.txt";

  # ai-agents-server.nix enables codex for lord; this host is Claude +
  # OpenCode only.
  programs.codex.enable = lib.mkForce false;

  programs.home-manager.enable = true;
}
