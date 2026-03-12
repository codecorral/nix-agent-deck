{
  description = "Example: using nix-agent-deck with llm-agents.nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-agent-deck = {
      url = "github:codecorral/nix-agent-deck";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:asheshgoplani/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nix-agent-deck, llm-agents, ... }:
    let
      system = "x86_64-linux"; # or "aarch64-darwin" for macOS
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          nix-agent-deck.homeManagerModules.default
          {
            home.username = "user";
            home.homeDirectory = "/home/user";
            home.stateVersion = "24.05";

            # Install agent-deck from llm-agents.nix
            home.packages = [
              llm-agents.packages.${system}.agent-deck
            ];

            # Declarative agent-deck configuration
            programs.agent-deck = {
              enable = true;
              defaultTool = "claude";

              claude = {
                allowDangerousMode = true;
                envFile = "~/.claude.env";
              };

              shell.envFiles = [ "~/.agent-deck.env" ];

              mcps.github = {
                command = "npx";
                args = [ "-y" "@modelcontextprotocol/server-github" ];
                env = { GITHUB_TOKEN = "\${GITHUB_TOKEN}"; };
              };

              profiles.work.claude.configDir = "~/.claude-work";
            };
          }
        ];
      };
    };
}
