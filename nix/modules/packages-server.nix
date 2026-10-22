{
  config,
  pkgs,
  pkgs-unstable,
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
    forgejo-cli

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
    opentofu
    google-cloud-sdk
    doctl

    # ── AI / LLM CLIs ──────────────────────────────────────────────────────────
    # Same llm-agents.nix store paths as desktop (cache.numtide.com). Orca
    # remote server detects `claude`/`codex`/`opencode2` on PATH.
    # claude-code and codex come via programs.* in ai-agents-server.nix.
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
  ];
}
