{ notifications, ... }:

{
  # Home Manager needs to know the user and home directory.
  home.username = "boss";
  home.homeDirectory = "/home/boss";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards-incompatible changes.
  #
  # You should NOT change this value, even if you update Home Manager. If you
  # do want to update the value, first check the Home Manager release notes:
  # https://nix-community.github.io/home-manager/release-notes.xhtml
  home.stateVersion = "24.11";

  # Allow non-free (proprietary) packages.
  # Needed for: VS Code, Steam, and other proprietary software.
  nixpkgs.config.allowUnfree = true;

  # llm-agents.nix packages (claude-code, codex, cursor-agent, ...) are consumed
  # directly via `llm-agents.packages.${pkgs.stdenv.hostPlatform.system}` in packages.nix and
  # ai-agents.nix, NOT through nixpkgs.overlays. The overlay
  # (llm-agents.overlays.shared-nixpkgs) rebuilds each package against *our*
  # nixpkgs revision, which almost never matches numtide's own pinned
  # nixpkgs — so every package silently compiles locally instead of hitting
  # numtide's binary cache (cache.numtide.com). Using the flake's packages
  # output directly gets the exact store paths numtide already built and
  # cached.

  imports = [
    ./modules/packages.nix   # All home.packages (replaces apt/brew/pipx/npm lists)
    ./modules/shell-apps.nix # home.programs.* for shell/CLI apps
    ./modules/ai-agents.nix  # Claude Code, Codex, OpenCode, MCP server registry, statusline
    ./modules/editors.nix    # Neovim, micro, VS Code/VSCodium settings, MarkText
    ./modules/agent-skills.nix # Claude Code user skills (dotfiles/agent-skills + Orca skills from flake input)
    ./modules/firefox.nix    # Firefox: profiles, shared settings, search engines, cookie policy
    ./modules/gui-apps.nix   # home.programs.* for GUI apps (Rofi, OBS)
    ./modules/shell.nix      # Shell environment, PATH additions, aliases
    ./modules/distrobox.nix  # Declarative distrobox container definitions
    ./modules/sops-age-key.nix # sops age identity: Secret Service → $XDG_RUNTIME_DIR (sops.age.keyFile)
    ./modules/rclone.nix     # Declarative rclone remotes (sops-encrypted credentials)
    ./modules/ai-secrets.nix # sops-encrypted AI provider keys (OpenRouter → Tray-Links, FreeLLMAPI → OpenCode)
    ./modules/services.nix   # User-level systemd services (ollama, etc.)
    ./modules/gpg-expiry.nix # Weekly check for GPG keys near expiry
    ./modules/cass.nix       # cass agent-session search: background index timers (cass itself via Brewfile)
    ./modules/transcript-scrub.nix # Daily gitleaks scrub of secrets in agent transcripts (scripts/security/)
    ./modules/weekly-cleanup.nix # Weekly Nix GC + Docker prune (shared with lord-ubuntu)
    notifications.homeManagerModules.desktop # KDE notifications + notify CLI from the Notifications hub
    ./modules/recoll.nix     # Recoll full-text document index (~/Documents, ~/Downloads, ~/Media) + hourly timer
    ./modules/desktop.nix    # Desktop autostarts (Solaar, VeraCrypt, Tailscale tray) + xdg-open/ft-mpv wrappers
  ];

  # KDE desktop notifications from the Notifications hub on lord-ubuntu:
  # a systemd user service runs `ntfy subscribe desktop-boss` and turns each
  # message into a notify-send popup (with Click/view-action buttons). The
  # `notify` CLI for sending is on PATH. Receivers/routes live in
  # Self-Hosted/Notifications/notifications.yml.
  services.notifications-desktop = {
    enable = true;
    topic = "desktop-boss";
  };

  # Tell Home Manager this is a non-NixOS Linux system.
  # This auto-enables targets.genericLinux.gpu, which creates
  # /run/opengl-driver → Nix Mesa derivation so that Nix-packaged
  # GPU apps (Qt6, etc.) can find the OpenGL/Vulkan driver.
  targets.genericLinux.enable = true;

  # Export XDG_{CONFIG,DATA,STATE,CACHE}_HOME via home.sessionVariables so
  # tools (and xdg-ninja) see explicit values instead of relying on defaults.
  xdg.enable = true;

  # Make HM-provided program modules that support it (currently: readline,
  # codex — see modules/programs/*.nix upstream) write to XDG paths instead of
  # $HOME directly. Part of the xdg-ninja migration; safer than hand-rolled
  # env vars for these two since HM manages the file *and* the var together.
  home.preferXdgDirectories = true;

  # Register Nix-installed fonts with the system fontconfig.
  # Required on non-NixOS — without this, fonts in the Nix store are invisible
  # to GTK apps (like Lutris) even if the packages are installed.
  fonts.fontconfig.enable = true;

  # Pin the generic fontconfig families. KDE has no font config of its own in
  # ~/.config/kdeglobals, so the value of `sans-serif` here is what shows up in
  # the KDE chrome (Dolphin path bar, Yakuake tabs, Konsole menus, etc.).
  # Without this, a nixpkgs roll-forward can swap the resolved font (or its
  # build) and visibly shift the rendering. `binding="strong"` overrides the
  # weak defaults baked into noto-fonts / fontconfig.
  home.file.".config/fontconfig/conf.d/53-default-families.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <alias binding="strong">
        <family>sans-serif</family>
        <prefer><family>Noto Sans</family></prefer>
      </alias>
      <alias binding="strong">
        <family>serif</family>
        <prefer><family>Noto Serif</family></prefer>
      </alias>
      <alias binding="strong">
        <family>monospace</family>
        <prefer><family>Noto Sans Mono</family></prefer>
      </alias>
    </fontconfig>
  '';

  # Let Home Manager manage itself. This generates the home-manager CLI
  # and enables automatic profile updates.
  programs.home-manager.enable = true;
}
