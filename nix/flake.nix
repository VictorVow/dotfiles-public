{
  description = "Home Manager configuration for boss's Kubuntu system";

  inputs = {
    # Pinned to a commit at least PIN_AGE_DAYS days old on its upstream branch
    # (see update.sh). The age-pin gives Hydra time to fully populate its
    # binary cache, so home-manager switch downloads pre-built artifacts
    # rather than compiling from source. The `# channel:` comment above each
    # url records the upstream branch so update.sh can advance the pin on the
    # next run; the SHA in the url is what nix flake update resolves into
    # flake.lock. Don't hand-edit the SHAs — let update.sh do it.

    # channel: nixos-26.05
    nixpkgs.url = "github:NixOS/nixpkgs/1c8cb0ef7d0e07458e866196fb1a239e30129b57";

    # channel: nixos-unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/bf546038f89a0116b479f629f160422b9af06a06";

    home-manager = {
      # channel: release-26.05
      url = "github:nix-community/home-manager/fd0956c99c41ae3c13a73a638f1f7e963aebc4ab";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management — decrypts age-encrypted secrets (nix/secrets/*.yaml)
    # at activation. Used by modules/rclone.nix for rclone remote credentials.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — removed; was github:aaddrick/claude-desktop-debian.
    # The flake rebuilt a Debian .deb on every lock bump. Now installed via
    # custom-installers.yml from the upstream .deb release.

    # AI coding tools — own binary cache at cache.numtide.com, rebuilt daily.
    # Age-pinned to a ≥PIN_AGE_DAYS_LLM_AGENTS-day-old commit (see update.sh) so
    # a `nix flake update` never lands on a same-day commit numtide hasn't
    # published a cache for yet — that forced hms to compile gemini/codex
    # locally instead of downloading. The pin floor is much shorter than
    # nixpkgs' PIN_AGE_DAYS since numtide's cache catches up within a day.
    # Also intentionally NOT following nixpkgs so the pre-built packages in
    # numtide's cache (built against unstable) remain valid store paths.
    # channel: main
    llm-agents.url = "github:numtide/llm-agents.nix/b2cd845e480db876dada4d02bb832fa8bf1e55cc";

    # Tiny single-purpose flakes — not age-pinned because they barely change
    # and don't pull in the heavy nixpkgs rebuild surface that motivated the
    # age pin in the first place.
    tuxManager.url = "github:benapetr/TuxManager/";
    tuxManager.inputs.nixpkgs.follows = "nixpkgs";

    ie-r.url = "github:miaupaw/ie-r";

    # Zed's Delta (official prebuilt Linux binaries, wrapped for Nix).
    delta.url = "github:zed-industries/delta-nix";
    delta.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, llm-agents, tuxManager, ie-r, delta, sops-nix, ... }: {
    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix sops-nix.homeManagerModules.sops ];

      extraSpecialArgs = {
        inherit llm-agents tuxManager ie-r delta;
        pkgs-unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
        hostProfile = {
          hms = {
            flakePath  = "$HOME/Projects/installs/nix";
            configName = "boss";
          };
        };
      };
    };
  };
}
