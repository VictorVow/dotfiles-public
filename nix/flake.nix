{
  description = "Home Manager configuration for boss's Kubuntu system";

  inputs = {
    # Using nixpkgs-unstable for the latest package versions.
    # Switch to "github:nixos/nixpkgs/nixos-24.11" for a stable channel.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # Ensure home-manager uses the same nixpkgs as above to avoid
      # building with two different versions of the package set.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, claude-desktop, ... }: {
    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix ];

      extraSpecialArgs = { inherit claude-desktop; };
    };
  };
}
