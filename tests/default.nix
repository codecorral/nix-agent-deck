{ pkgs, home-manager }:

let
  lib = pkgs.lib;
  tomlFormat = pkgs.formats.toml { };

  # Evaluate a Home Manager config with our module
  eval = hmConfig:
    let
      result = lib.evalModules {
        modules = [
          home-manager.homeManagerModules.default
          ../modules/agent-deck.nix
          {
            home.stateVersion = "24.05";
            home.homeDirectory = "/home/test";
            home.username = "test";
          }
          hmConfig
        ];
        specialArgs = { inherit pkgs; };
      };
    in result.config;

  # Extract the generated TOML content as an attrset by reading the source derivation
  getToml = hmConfig:
    let cfg = eval hmConfig;
    in builtins.fromTOML (builtins.readFile cfg.home.file.".agent-deck/config.toml".source);

  # Test: minimal config (4.1)
  minimalConfig = getToml {
    programs.agent-deck.enable = true;
  };

  # Test: full config round-trip (4.2)
  fullConfig = getToml {
    programs.agent-deck = {
      enable = true;
      defaultTool = "codex";
      shell = {
        envFiles = [ "~/.agent-deck.env" ".env" ];
        initScript = "echo hello";
        ignoreMissingEnvFiles = true;
      };
      claude = {
        configDir = "~/.claude-custom";
        dangerousMode = true;
        allowDangerousMode = true;
        envFile = "~/.claude.env";
      };
      codex.yoloMode = true;
      docker = {
        defaultEnabled = true;
        defaultImage = "ubuntu:22.04";
        cpuLimit = "2";
        memoryLimit = "4g";
        mountSsh = true;
        autoCleanup = true;
        environment = [ "FOO=bar" ];
        volumeIgnores = [ "node_modules" ".git" ];
      };
      logs = {
        maxSizeMb = 50;
        maxLines = 20000;
        removeOrphans = false;
      };
      updates = {
        autoUpdate = true;
        checkEnabled = false;
        checkIntervalHours = 12;
        notifyInCli = false;
      };
      globalSearch = {
        enabled = true;
        tier = "instant";
        memoryLimitMb = 200;
        recentDays = 30;
        indexRateLimit = 10;
      };
      mcpPool = {
        enabled = true;
        autoStart = true;
        poolAll = true;
        excludeMcps = [ "local-dev" ];
        fallbackToStdio = false;
        showPoolStatus = true;
      };
    };
  };

  # Test: MCP definitions (4.3)
  mcpConfig = getToml {
    programs.agent-deck = {
      enable = true;
      mcps = {
        github = {
          command = "npx";
          args = [ "-y" "@modelcontextprotocol/server-github" ];
          env = { GITHUB_TOKEN = "\${GITHUB_TOKEN}"; };
        };
        remote = {
          url = "https://api.example.com/mcp";
          transport = "http";
        };
      };
    };
  };

  # Test: profile override (4.4)
  profileConfig = getToml {
    programs.agent-deck = {
      enable = true;
      profiles.work.claude.configDir = "~/.claude-work";
    };
  };

  # Test: extraConfig merge (4.5)
  extraConfigResult = getToml {
    programs.agent-deck = {
      enable = true;
      claude.configDir = "~/.claude";
      extraConfig = {
        claude = { new_field = true; };
        some_new_section = { key = "value"; };
      };
    };
  };

  # Test: empty section omission (4.6)
  emptyConfig = getToml {
    programs.agent-deck = {
      enable = true;
      defaultTool = "claude";
    };
  };

  # Assertion helpers
  assertEq = name: actual: expected:
    if actual == expected then true
    else builtins.throw "${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

  assertHasAttr = name: set: attr:
    if set ? ${attr} then true
    else builtins.throw "${name}: missing attribute '${attr}' in ${builtins.toJSON set}";

  assertNoAttr = name: set: attr:
    if !(set ? ${attr}) then true
    else builtins.throw "${name}: unexpected attribute '${attr}' in ${builtins.toJSON set}";

in
{
  # 4.1: Minimal config evaluation test
  minimal-config = pkgs.runCommand "test-minimal-config" { } ''
    ${lib.optionalString (
      (assertEq "minimal has default_tool" minimalConfig.default_tool "claude")
      && (assertNoAttr "no shell section" minimalConfig "shell")
      && (assertNoAttr "no claude section" minimalConfig "claude")
    ) ""}
    echo "minimal config test passed" > $out
  '';

  # 4.2: Full config round-trip test
  full-config = pkgs.runCommand "test-full-config" { } ''
    ${lib.optionalString (
      (assertEq "default_tool" fullConfig.default_tool "codex")
      && (assertHasAttr "shell section" fullConfig "shell")
      && (assertEq "env_files" fullConfig.shell.env_files [ "~/.agent-deck.env" ".env" ])
      && (assertEq "init_script" fullConfig.shell.init_script "echo hello")
      && (assertHasAttr "claude section" fullConfig "claude")
      && (assertEq "config_dir" fullConfig.claude.config_dir "~/.claude-custom")
      && (assertEq "dangerous_mode" fullConfig.claude.dangerous_mode true)
      && (assertHasAttr "codex section" fullConfig "codex")
      && (assertEq "yolo_mode" fullConfig.codex.yolo_mode true)
      && (assertHasAttr "docker section" fullConfig "docker")
      && (assertEq "default_enabled" fullConfig.docker.default_enabled true)
      && (assertEq "cpu_limit" fullConfig.docker.cpu_limit "2")
      && (assertEq "mount_ssh" fullConfig.docker.mount_ssh true)
      && (assertEq "volume_ignores" fullConfig.docker.volume_ignores [ "node_modules" ".git" ])
      && (assertHasAttr "logs section" fullConfig "logs")
      && (assertEq "max_size_mb" fullConfig.logs.max_size_mb 50)
      && (assertHasAttr "updates section" fullConfig "updates")
      && (assertEq "check_enabled" fullConfig.updates.check_enabled false)
      && (assertHasAttr "global_search section" fullConfig "global_search")
      && (assertEq "tier" fullConfig.global_search.tier "instant")
      && (assertEq "memory_limit_mb" fullConfig.global_search.memory_limit_mb 200)
      && (assertHasAttr "mcp_pool section" fullConfig "mcp_pool")
      && (assertEq "pool_all" fullConfig.mcp_pool.pool_all true)
      && (assertEq "exclude_mcps" fullConfig.mcp_pool.exclude_mcps [ "local-dev" ])
    ) ""}
    echo "full config test passed" > $out
  '';

  # 4.3: MCP definition test
  mcp-definitions = pkgs.runCommand "test-mcp-definitions" { } ''
    ${lib.optionalString (
      (assertHasAttr "mcps section" mcpConfig "mcps")
      && (assertHasAttr "github mcp" mcpConfig.mcps "github")
      && (assertEq "github command" mcpConfig.mcps.github.command "npx")
      && (assertEq "github args" mcpConfig.mcps.github.args [ "-y" "@modelcontextprotocol/server-github" ])
      && (assertHasAttr "github env" mcpConfig.mcps.github "env")
      && (assertHasAttr "remote mcp" mcpConfig.mcps "remote")
      && (assertEq "remote url" mcpConfig.mcps.remote.url "https://api.example.com/mcp")
      && (assertEq "remote transport" mcpConfig.mcps.remote.transport "http")
    ) ""}
    echo "mcp definitions test passed" > $out
  '';

  # 4.4: Profile override test
  profile-override = pkgs.runCommand "test-profile-override" { } ''
    ${lib.optionalString (
      (assertHasAttr "profiles section" profileConfig "profiles")
      && (assertHasAttr "work profile" profileConfig.profiles "work")
      && (assertHasAttr "work claude" profileConfig.profiles.work "claude")
      && (assertEq "work config_dir" profileConfig.profiles.work.claude.config_dir "~/.claude-work")
    ) ""}
    echo "profile override test passed" > $out
  '';

  # 4.5: Extra config merge test
  extra-config-merge = pkgs.runCommand "test-extra-config-merge" { } ''
    ${lib.optionalString (
      (assertHasAttr "claude section" extraConfigResult "claude")
      && (assertEq "typed config_dir preserved" extraConfigResult.claude.config_dir "~/.claude")
      && (assertEq "extra new_field merged" extraConfigResult.claude.new_field true)
      && (assertHasAttr "new section" extraConfigResult "some_new_section")
      && (assertEq "new section key" extraConfigResult.some_new_section.key "value")
    ) ""}
    echo "extra config merge test passed" > $out
  '';

  # 4.6: Empty section omission test
  empty-section-omission = pkgs.runCommand "test-empty-section-omission" { } ''
    ${lib.optionalString (
      (assertEq "default_tool present" emptyConfig.default_tool "claude")
      && (assertNoAttr "no shell section" emptyConfig "shell")
      && (assertNoAttr "no docker section" emptyConfig "docker")
      && (assertNoAttr "no logs section" emptyConfig "logs")
      && (assertNoAttr "no updates section" emptyConfig "updates")
      && (assertNoAttr "no global_search section" emptyConfig "global_search")
      && (assertNoAttr "no mcp_pool section" emptyConfig "mcp_pool")
      && (assertNoAttr "no mcps section" emptyConfig "mcps")
      && (assertNoAttr "no tools section" emptyConfig "tools")
      && (assertNoAttr "no profiles section" emptyConfig "profiles")
    ) ""}
    echo "empty section omission test passed" > $out
  '';
}
