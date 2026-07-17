{ config, pkgs, lib, tuxManager, ... }:

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

  # llm-agents.nix packages (claude-code, codex, gemini-cli, ...) are consumed
  # directly via `llm-agents.packages.${pkgs.system}` in packages.nix and
  # shell-apps.nix, NOT through nixpkgs.overlays. The overlay
  # (llm-agents.overlays.shared-nixpkgs) rebuilds each package against *our*
  # nixpkgs revision, which almost never matches numtide's own pinned
  # nixpkgs — so every package silently compiles locally instead of hitting
  # numtide's binary cache (cache.numtide.com). Using the flake's packages
  # output directly gets the exact store paths numtide already built and
  # cached.

  imports = [
    ./modules/packages.nix   # All home.packages (replaces apt/brew/pipx/npm lists)
    ./modules/shell-apps.nix # home.programs.* for shell/CLI apps
    ./modules/gui-apps.nix   # home.programs.* for GUI apps (Firefox, Zed, Rofi)
    ./modules/shell.nix      # Shell environment, PATH additions, aliases
    ./modules/distrobox.nix  # Declarative distrobox container definitions
    ./modules/rclone.nix     # Declarative rclone remotes (sops-encrypted credentials)
    ./modules/ai-secrets.nix # OpenRouter API key for Tray-Links "ai" tray (sops-encrypted)
    ./modules/services.nix   # User-level systemd services (ollama, etc.)
    ./modules/gpg-expiry.nix # Weekly check for GPG keys near expiry
    ./modules/desktop.nix    # Desktop autostarts (Solaar, VeraCrypt, Tailscale tray) + xdg-open/ft-mpv wrappers
  ];

  # Tell Home Manager this is a non-NixOS Linux system.
  # This auto-enables targets.genericLinux.gpu, which creates
  # /run/opengl-driver → Nix Mesa derivation so that Nix-packaged
  # GPU apps (Qt6, etc.) can find the OpenGL/Vulkan driver.
  targets.genericLinux.enable = true;

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
