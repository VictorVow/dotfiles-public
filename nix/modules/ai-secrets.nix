{ config, ... }:

# Sops-encrypted AI provider keys. ../secrets/ai.yaml is the canonical store:
# the Tray-Links "ai" tray reads openrouter_api_key from the sops-nix default
# symlink dir (~/.config/sops-nix/secrets/, backed by tmpfs under
# /run/user/<uid>/secrets.d/), and FreeLLMAPI's deploy.yml (Self-Hosted repo)
# decrypts the same file with `sops -d` to render its provider-key config —
# keys NOT declared under sops.secrets here stay inside the encrypted file
# (never materialized by home-manager). Same pattern as ../secrets/rclone.yaml
# (see modules/rclone.nix): no `path` override, the secret lives only on tmpfs.
{
  sops = {
    # age.keyFile is set centrally in modules/sops-age-key.nix (materialised
    # from Secret Service at login).
    secrets."openrouter_api_key" = {
      sopsFile = ../secrets/ai.yaml;
    };
    # FreeLLMAPI unified key (dashboard Keys page header), for OpenCode's
    # `freellmapi` provider (see modules/ai-agents.nix). Kept on the explicit
    # path because the opencode wrapper and `with-secret freellmapi`
    # (shell.nix) reference ~/.config/shell-secrets/freellmapi_api_key
    # directly — unlike rclone/tray-links there's no .path consumer.
    secrets."freellmapi_api_key" = {
      sopsFile = ../secrets/ai.yaml;
      path = "${config.home.homeDirectory}/.config/shell-secrets/freellmapi_api_key";
    };
  };

  # Deliberately not OPENAI_API_KEY/ANTHROPIC_AUTH_TOKEN: those would shadow
  # real provider auth in other agent CLIs. Only OpenCode's provider reads this.
  # Set as FREELLMAPI_API_KEY only by the opencode/opencode2 wrapper
  # (packages.nix) and `with-secret freellmapi` (shell.nix) — never exported.
}
