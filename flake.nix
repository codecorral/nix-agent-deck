{
  description = "Home Manager module for agent-deck configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, home-manager, flake-utils }:
    {
      homeManagerModules.agent-deck = import ./modules/agent-deck.nix;
      homeManagerModules.default = self.homeManagerModules.agent-deck;
    }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        checks = import ./tests {
          inherit pkgs;
          home-manager = home-manager;
        };
      }
    );
}
