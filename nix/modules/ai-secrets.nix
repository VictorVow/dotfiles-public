{ config, ... }:

# Sops-encrypted AI provider keys. ../secrets/ai.yaml is the canonical store:
# the Tray-Links "ai" tray reads openrouter_api_key via the sops-nix secret
# below, and FreeLLMAPI's deploy.yml (Self-Hosted repo) decrypts the same file
# with `sops -d` to render its provider-key config — keys NOT declared under
# sops.secrets here stay inside the encrypted file (never materialized by
# home-manager). Same pattern as ../secrets/rclone.yaml (see modules/rclone.nix).
# Unlike rclone's secrets, tray-links' are read directly by a plain Python
# script rather than by another Home Manager module, so each declared secret
# gets an explicit, stable `path` instead of the sops-nix default under
# /run/user/<uid>/...
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    secrets."openrouter_api_key" = {
      sopsFile = ../secrets/ai.yaml;
      path = "${config.home.homeDirectory}/.config/tray-links/openrouter_api_key";
    };
  };
}
