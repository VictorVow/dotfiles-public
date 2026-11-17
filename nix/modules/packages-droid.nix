{
  config,
  pkgs,
  pkgs-unstable,
  llm-agents,
  ...
}:

# Minimal package set for droid (Pixel AVF Debian VM, aarch64-linux).
# Trimmed from packages-server.nix: no IaC tools (ansible/tofu/gcloud/doctl),
# no rclone/mosh/gitleaks, no extra agent CLIs beyond what ai-agents-server.nix
# configures. Keep this small — the VM lives on phone storage.
let
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = with pkgs; [
    # ── Shell / CLI ────────────────────────────────────────────────────────────
    procps # pgrep, ps, kill
    btop
    fastfetch
    ripgrep
    fd
    jq
    tmux # configured by programs.tmux in shell-apps.nix
    eza
    micro # EDITOR/VISUAL in shell-server.nix

    # ── Version control ────────────────────────────────────────────────────────
    git

    # ── Runtimes / dev tools ───────────────────────────────────────────────────
    uv
    nodejs_24 # ponytail plugin hooks run `node` (ai-agents-server.nix)
    python3 # bash-secret-guard.py + statusline.py hooks
    just

    # ── Secrets ────────────────────────────────────────────────────────────────
    sops
    age
    gnupg

    # ── Networking / remote ────────────────────────────────────────────────────
    tailscale # CLI only — tailscaled is a system service (apt), already enrolled
    android-tools # adb

    # ── AI / LLM CLIs ──────────────────────────────────────────────────────────
    # claude-code and opencode2 come via programs.* in ai-agents-server.nix;
    # these are the wrappers/tools it doesn't provide.
    pkgs-unstable.devin-cli
    # opencode2 wrapped to read the provider keys from their sops files — same
    # pattern as packages-server.nix (secrets come from ai-secrets-droid.nix).
    (pkgs.symlinkJoin {
      name = "opencode2-wrapped";
      paths = [ llmAgents.opencode2 ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/opencode2
        makeWrapper ${llmAgents.opencode2}/bin/opencode2 $out/bin/opencode2 \
          --run 'export FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"' \
          --run 'export REFUSELESS_API_KEY="$(cat ${config.sops.secrets.refuseless_api_key.path} 2>/dev/null)"'
      '';
    })
    # OpenCode 1 (`opencode`/`opencode1`) for the magpie Devin/Cursor plugins —
    # same isolated ~/.opencode1 wrapper as packages-server.nix (config in
    # ai-agents-server.nix).
    (pkgs.symlinkJoin {
      name = "opencode1-wrapped";
      paths = [
        (pkgs.writeShellScriptBin "opencode1" ''
          root="$HOME/.opencode1"
          FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"
          export FREELLMAPI_API_KEY
          REFUSELESS_API_KEY="$(cat ${config.sops.secrets.refuseless_api_key.path} 2>/dev/null)"
          export REFUSELESS_API_KEY
          export XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" \
                 XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache"
          # Mirror ~/.config into the isolated root, except v2's `opencode`.
          for d in "$HOME"/.config/* "$HOME"/.config/.[!.]*; do
            [ -e "$d" ] || continue
            base=''${d##*/}
            [ "$base" = opencode ] && continue
            [ -e "$root/config/$base" ] || ln -s "$d" "$root/config/$base"
          done
          # Drop v2's `--standalone`, which v1 doesn't know.
          args=()
          for a in "$@"; do [ "$a" = --standalone ] || args+=("$a"); done
          exec ${llmAgents.opencode}/bin/opencode "''${args[@]}"
        '')
      ];
      postBuild = "ln -s opencode1 $out/bin/opencode";
    })
  ];
}
