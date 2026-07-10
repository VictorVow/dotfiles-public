{ config, ... }:

# Sops-encrypted API keys for the Tray-Links "ai" tray (System-Tray-App repo).
# Secrets live encrypted (age) in ../secrets/ai.yaml, same pattern as
# ../secrets/rclone.yaml (see modules/rclone.nix). Unlike rclone's secrets,
# these are read directly by a plain Python script rather than by another
# Home Manager module, so each secret gets an explicit, stable `path` instead
# of the sops-nix default under /run/user/<uid>/...
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    secrets."openrouter_api_key" = {
      sopsFile = ../secrets/ai.yaml;
      path = "${config.home.homeDirectory}/.config/tray-links/openrouter_api_key";
    };
  };
}
