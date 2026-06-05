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
    nixpkgs.url = "github:NixOS/nixpkgs/e1353d7f24e91422a2951ce49afaf96e6ea27761";

    # channel: nixos-unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/e1353d7f24e91422a2951ce49afaf96e6ea27761";

    home-manager = {
      # channel: release-26.05
      url = "github:nix-community/home-manager/866412a19866b4a8e32d2306a118040afa2b840c";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — removed; was github:aaddrick/claude-desktop-debian.
    # The flake rebuilt a Debian .deb on every lock bump. Now installed via
    # custom-installers.yml from the upstream .deb release.

    # AI coding tools — auto-updated daily, own binary cache at cache.numtide.com.
    # Intentionally NOT age-pinned: numtide rebuilds and re-publishes the cache
    # daily for HEAD, so an old pin would just miss the cache. Also intentionally
    # NOT following nixpkgs so the pre-built packages in numtide's cache (built
    # against unstable) remain valid store paths — cache hits work.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Tiny single-purpose flakes — not age-pinned because they barely change
    # and don't pull in the heavy nixpkgs rebuild surface that motivated the
    # age pin in the first place.
    tuxManager.url = "github:benapetr/TuxManager/";
    tuxManager.inputs.nixpkgs.follows = "nixpkgs";

    ie-r.url = "github:miaupaw/ie-r";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, llm-agents, tuxManager, ie-r, ... }: {
    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix ];

      extraSpecialArgs = {
        inherit llm-agents tuxManager ie-r;
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
