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
  ];

  # Let Home Manager manage itself. This generates the home-manager CLI
  # and enables automatic profile updates.
  programs.home-manager.enable = true;
}
