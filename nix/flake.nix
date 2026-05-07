{
  description = "Home Manager configuration for boss's Kubuntu system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — removed; was github:aaddrick/claude-desktop-debian.
    # The flake rebuilt a Debian .deb on every lock bump. Now installed via
    # custom-installers.yml from the upstream .deb release.

    # AI coding tools — auto-updated daily, own binary cache at cache.numtide.com.
    # Intentionally NOT following nixpkgs so the pre-built packages in numtide's
    # cache (built against unstable) remain valid store paths — cache hits work.
    llm-agents.url = "github:numtide/llm-agents.nix";

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
      };
    };
  };
}
