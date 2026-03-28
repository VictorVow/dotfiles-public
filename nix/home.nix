{ config, pkgs, lib, ... }:

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

  imports = [
    ./modules/packages.nix   # All home.packages (replaces apt/brew/pipx/npm lists)
    ./modules/programs.nix   # home.programs.* configurations
    ./modules/shell.nix      # Shell environment, PATH additions, aliases
    ./modules/distrobox.nix  # Declarative distrobox container definitions
    ./modules/services.nix   # User-level systemd services (ollama, etc.)
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

  # Let Home Manager manage itself. This generates the home-manager CLI
  # and enables automatic profile updates.
  programs.home-manager.enable = true;

  # Start Solaar (Logitech device manager) in the system tray on login.
  # Uses KDE autostart (.desktop) instead of a systemd service so that
  # hms doesn't restart it (and open a window) on every home-manager switch.
  home.file.".config/autostart/solaar.desktop".text = ''
    [Desktop Entry]
    Name=Solaar
    Exec=${pkgs.solaar}/bin/solaar --window=hide
    Type=Application
    X-KDE-autostart-after=panel
  '';

  # Start VeraCrypt background task in the system tray on login.
  # WAYLAND_DISPLAY is unset so wxWidgets falls back to the XEmbed tray
  # protocol via XWayland, where xembedsniproxy bridges it to KDE's SNI tray.
  home.file.".config/autostart/veracrypt.desktop".text = ''
    [Desktop Entry]
    Name=VeraCrypt
    Exec=env WAYLAND_DISPLAY= ${pkgs.veracrypt}/bin/veracrypt --background-task
    Type=Application
    X-KDE-autostart-after=panel
  '';
}
