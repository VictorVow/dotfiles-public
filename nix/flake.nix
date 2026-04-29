{
  description = "Home Manager configuration for boss's Kubuntu system";

  nixConfig = {
    extra-substituters      = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI coding tools — auto-updated daily, own binary cache at cache.numtide.com.
    # Intentionally NOT following nixpkgs so the pre-built packages in numtide's
    # cache (built against unstable) remain valid store paths — cache hits work.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { nixpkgs, home-manager, claude-desktop, llm-agents, ... }: {
    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix ];

      extraSpecialArgs = { inherit claude-desktop llm-agents; };
    };
  };
}
