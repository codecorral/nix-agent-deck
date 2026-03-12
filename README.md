# nix-agent-deck

Home Manager module for declarative [agent-deck](https://github.com/asheshgoplani/agent-deck) configuration.

Generates `~/.agent-deck/config.toml` from typed Nix options with full validation for stable config sections and flexible `attrsOf` for dynamic sections (MCPs, tools).

## Usage

Add to your flake inputs and import the module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-agent-deck.url = "github:codecorral/nix-agent-deck";
    llm-agents.url = "github:asheshgoplani/llm-agents.nix";
  };

  outputs = { nixpkgs, home-manager, nix-agent-deck, llm-agents, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        nix-agent-deck.homeManagerModules.default
        {
          home.packages = [ llm-agents.packages.x86_64-linux.agent-deck ];
          programs.agent-deck = {
            enable = true;
            defaultTool = "claude";
          };
        }
      ];
    };
  };
}
```

## Examples

### Minimal

```nix
programs.agent-deck = {
  enable = true;
  defaultTool = "claude";
};
```

### Full config

```nix
programs.agent-deck = {
  enable = true;
  defaultTool = "claude";

  shell = {
    envFiles = [ "~/.agent-deck.env" ".env" ];
    initScript = "source ~/.zshrc";
    ignoreMissingEnvFiles = true;
  };

  claude = {
    configDir = "~/.claude";
    dangerousMode = true;
    allowDangerousMode = true;
    envFile = "~/.claude.env";
  };

  codex.yoloMode = false;

  docker = {
    defaultEnabled = false;
    defaultImage = "ubuntu:22.04";
    cpuLimit = "2";
    memoryLimit = "4g";
    mountSsh = true;
    autoCleanup = true;
    environment = [ "TERM=xterm-256color" ];
    volumeIgnores = [ "node_modules" ".git" ];
  };

  logs = {
    maxSizeMb = 10;
    maxLines = 10000;
    removeOrphans = true;
  };

  updates = {
    autoUpdate = false;
    checkEnabled = true;
    checkIntervalHours = 24;
    notifyInCli = true;
  };

  globalSearch = {
    enabled = true;
    tier = "auto";
    memoryLimitMb = 100;
    recentDays = 90;
    indexRateLimit = 20;
  };

  mcpPool = {
    enabled = false;
    autoStart = true;
    poolAll = false;
    fallbackToStdio = true;
    showPoolStatus = true;
  };

  worktree.defaultLocation = "sibling"; # or "subdirectory" or a custom path

  conductor = {
    enable = true;
    extraConfig = {
      auto_respond = true;
      telegram = {
        bot_token = "123:ABC";
        chat_id = "456";
      };
    };
  };
};
```

### MCP definitions

```nix
programs.agent-deck.mcps = {
  github = {
    command = "npx";
    args = [ "-y" "@modelcontextprotocol/server-github" ];
    env = { GITHUB_TOKEN = "\${GITHUB_TOKEN}"; };
  };
  remote-api = {
    url = "https://api.example.com/mcp";
    transport = "http";
  };
};
```

### Profiles

```nix
programs.agent-deck.profiles = {
  work.claude.configDir = "~/.claude-work";
  personal.claude.configDir = "~/.claude-personal";
};
```

### Secrets pattern (sops-nix)

The module does **not** manage secrets inline — API keys should never be in the Nix store. Use `envFile` references pointing to files managed by sops-nix or agenix:

```nix
{ config, ... }: {
  sops.secrets."agent-deck-env" = {
    sopsFile = ./secrets.yaml;
    path = "${config.home.homeDirectory}/.agent-deck.env";
  };

  programs.agent-deck = {
    enable = true;
    shell.envFiles = [ "~/.agent-deck.env" ];
    claude.envFile = "~/.claude.env";
  };
}
```

### Extra config (escape hatch)

For options not yet covered by typed options:

```nix
programs.agent-deck.extraConfig = {
  some_new_section = {
    key = "value";
  };
};
```

## Notes

- The generated config file is a read-only symlink from the Nix store. Agent-deck must not write to `config.toml` at runtime.
- Nix options use camelCase; generated TOML uses snake_case (mapped automatically).
- The module does not install agent-deck — add it to `home.packages` from `llm-agents.nix`.

## Tests

```bash
nix flake check
```
