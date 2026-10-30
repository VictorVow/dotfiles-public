{
  config,
  pkgs,
  pkgs-unstable,
  pkgs-latest,
  llm-agents,
  ...
}:

# Server subset of packages.nix — headless lord-ubuntu only.
# Anything GUI/desktop/hardware-adjacent stays in packages.nix. Keep this list
# small: the box runs ~25 self-hosted services already.
let
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = with pkgs; [
    # ── Shell / CLI ────────────────────────────────────────────────────────────
    procps # pgrep, ps, kill
    btop
    htop
    fastfetch
    ripgrep
    fd
    jq
    tmux # configured by programs.tmux in shell-apps.nix
    eza
    shellcheck
    lynx
    glow

    # ── Version control ────────────────────────────────────────────────────────
    git
    git-lfs
    git-filter-repo
    gh
    pkgs-latest.forgejo-cli # 0.7.0 fixes `fj repo view` panicking on mirrors; back to pkgs once the age pin has it

    # ── Runtimes / dev tools ───────────────────────────────────────────────────
    uv
    nodejs_24 # npm >= 11.10 for `min-release-age` (see programs.npm)
    fnm
    deno
    python3
    just
    ffmpeg
    yt-dlp

    # ── Secrets ────────────────────────────────────────────────────────────────
    sops
    age
    gitleaks
    gnupg
    libsecret # secret-tool, used by sops-age-key-server variant if enabled

    # ── Networking / remote ────────────────────────────────────────────────────
    mosh
    rclone # CLI only — remotes are boss-side (modules/rclone.nix is desktop)

    # ── Admin / IaC ────────────────────────────────────────────────────────────
    ansible
    opentofu # Terraform — open-source fork, CLI is `tofu`
    google-cloud-sdk
    doctl

    # ── AI / LLM CLIs ──────────────────────────────────────────────────────────
    # Same llm-agents.nix store paths as desktop (cache.numtide.com). Orca
    # remote server detects `claude`/`codex`/`opencode2`/`opencode`/`agy`
    # on PATH. claude-code and codex come via programs.* in ai-agents-server.nix.
    llmAgents.antigravity-cli # binary: `agy`
    llmAgents.cursor-agent
    llmAgents.copilot-cli
    pkgs-unstable.devin-cli
    # opencode2 wrapped to read FREELLMAPI_API_KEY from its sops file — same
    # pattern as packages.nix (sops secret comes from ai-secrets-server.nix).
    (pkgs.symlinkJoin {
      name = "opencode2-wrapped";
      paths = [ llmAgents.opencode2 ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/opencode2
        makeWrapper ${llmAgents.opencode2}/bin/opencode2 $out/bin/opencode2 \
          --run 'export FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"'
      '';
    })
    # OpenCode 1 (`opencode`/`opencode1`) for the magpie Devin/Cursor plugins —
    # same isolated ~/.opencode1 wrapper as packages.nix (config in ai-agents-server.nix).
    (pkgs.symlinkJoin {
      name = "opencode1-wrapped";
      paths = [
        (pkgs.writeShellScriptBin "opencode1" ''
          root="$HOME/.opencode1"
          FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"
          export FREELLMAPI_API_KEY
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
