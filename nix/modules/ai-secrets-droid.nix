{ config, ... }:

# Sops-encrypted AI provider keys for droid — a subset of ai-secrets.nix.
# ../secrets/ai-droid.yaml is encrypted to boss + droid only (see .sops.yaml);
# it carries just the two keys OpenCode's providers need on this host. The
# openrouter_api_key entry is skipped (no Tray-Links tray here), and the main
# ai.yaml stays boss+lord so the phone VM can't decrypt it.
{
  sops = {
    # age key: plaintext ~/.config/sops/age/keys.txt (sops-nix default) — see
    # home-droid.nix for why systemd-creds isn't used on this VM.
    secrets."freellmapi_api_key" = {
      sopsFile = ../secrets/ai-droid.yaml;
      path = "${config.home.homeDirectory}/.config/shell-secrets/freellmapi_api_key";
    };
    secrets."refuseless_api_key" = {
      sopsFile = ../secrets/ai-droid.yaml;
      path = "${config.home.homeDirectory}/.config/shell-secrets/refuseless_api_key";
    };
  };
}
