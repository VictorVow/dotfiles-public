{ ... }:

# Home Manager configuration for lord-ubuntu (headless server, user `lord`).
# See docs/system/lord-ubuntu-home.md.
{
  home.username = "lord";
  home.homeDirectory = "/home/lord";

  # Match desktop's stateVersion — determines HM release compat, unrelated to
  # when the config was created.
  home.stateVersion = "24.11";

  nixpkgs.config.allowUnfree = true;

  imports = [
    ./modules/packages-server.nix # headless package set
    ./modules/shell-apps.nix # programs.* — git/tmux/starship/htop/gh/direnv/ssh (all headless-safe)
    ./modules/ai-agents-server.nix # Claude Code/Codex/OpenCode2 (no browser MCPs)
    ./modules/shell-server.nix # bash env, hms/nsh/nr, trimmed of desktop bits
    ./modules/sops-age-key.nix # server branch: plaintext age key at ~/.config/sops/age/keys.txt
    ./modules/ai-secrets.nix # same sops ai.yaml → FREELLMAPI_API_KEY for opencode wrapper
    ./modules/cass.nix # agent-session index timers (needs ~/.local/bin/cass, see module)
    ./modules/transcript-scrub.nix # daily gitleaks scrub of agent transcripts
    ./modules/claude-skills.nix # ~/.claude/skills — desktop-only skills filtered out via hostProfile.isServer
  ];

  # Non-NixOS Linux (Ubuntu 26.04 on lord-ubuntu).
  targets.genericLinux.enable = true;

  xdg.enable = true;
  home.preferXdgDirectories = true;

  # No fonts/fontconfig — headless box.
  # No desktop.nix, gui-apps.nix, firefox.nix, distrobox.nix, rclone.nix,
  # recoll.nix, gpg-expiry.nix, services.nix, editors.nix — all desktop-coupled.

  programs.home-manager.enable = true;
}
