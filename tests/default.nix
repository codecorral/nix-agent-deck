{ pkgs, home-manager }:

let
  lib = pkgs.lib.extend (_: _: {
    hm = import "${home-manager}/modules/lib/default.nix" { lib = pkgs.lib; };
  });
  tomlFormat = pkgs.formats.toml { };

  # Evaluate a Home Manager config with our module
  hmModules = import "${home-manager}/modules/modules.nix" {
    inherit pkgs lib;
    check = false;
  };

  eval = hmConfig:
    let
      result = lib.evalModules {
        modules = hmModules ++ [
          ../modules/agent-deck.nix
          {
            home.stateVersion = "24.05";
            home.homeDirectory = "/home/test";
            home.username = "test";
          }
          hmConfig
        ];
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

  # Test: worktree section (issue #2)
  worktreeConfig = getToml {
    programs.agent-deck = {
      enable = true;
      worktree.defaultLocation = "subdirectory";
    };
  };

  # Test: conductor enable only
  conductorEnableConfig = getToml {
    programs.agent-deck = {
      enable = true;
      conductor.enable = true;
    };
  };

  # Test: conductor with extraConfig
  conductorFullConfig = getToml {
    programs.agent-deck = {
      enable = true;
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
  };

  # Test: conductor extraConfig without enable
  conductorExtraOnlyConfig = getToml {
    programs.agent-deck = {
      enable = true;
      conductor.extraConfig = { auto_respond = false; };
    };
  };

  # Test: worktree with custom path
  worktreeCustomConfig = getToml {
    programs.agent-deck = {
      enable = true;
      worktree.defaultLocation = "/tmp/worktrees";
    };
  };

  # Test: skillSources option
  skillSourcesConfig = eval {
    programs.agent-deck = {
      enable = true;
      skillSources = {
        linkding = ./mock-skill-dir;
      };
    };
  };

  # Test: empty skillSources (no pool entries)
  emptySkillSourcesConfig = eval {
    programs.agent-deck = {
      enable = true;
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
      && (assertNoAttr "no worktree section" emptyConfig "worktree")
      && (assertNoAttr "no conductor section" emptyConfig "conductor")
    ) ""}
    echo "empty section omission test passed" > $out
  '';

  # Worktree section test
  worktree-section = pkgs.runCommand "test-worktree-section" { } ''
    ${lib.optionalString (
      (assertHasAttr "worktree section" worktreeConfig "worktree")
      && (assertEq "default_location" worktreeConfig.worktree.default_location "subdirectory")
    ) ""}
    echo "worktree section test passed" > $out
  '';

  # Conductor enable only test
  conductor-enable = pkgs.runCommand "test-conductor-enable" { } ''
    ${lib.optionalString (
      (assertHasAttr "conductor section" conductorEnableConfig "conductor")
      && (assertEq "conductor enable" conductorEnableConfig.conductor.enable true)
    ) ""}
    echo "conductor enable test passed" > $out
  '';

  # Conductor with extraConfig test
  conductor-full = pkgs.runCommand "test-conductor-full" { } ''
    ${lib.optionalString (
      (assertHasAttr "conductor section" conductorFullConfig "conductor")
      && (assertEq "conductor enable" conductorFullConfig.conductor.enable true)
      && (assertEq "conductor auto_respond" conductorFullConfig.conductor.auto_respond true)
      && (assertHasAttr "conductor telegram" conductorFullConfig.conductor "telegram")
      && (assertEq "telegram bot_token" conductorFullConfig.conductor.telegram.bot_token "123:ABC")
      && (assertEq "telegram chat_id" conductorFullConfig.conductor.telegram.chat_id "456")
    ) ""}
    echo "conductor full test passed" > $out
  '';

  # Conductor extraConfig without enable test
  conductor-extra-only = pkgs.runCommand "test-conductor-extra-only" { } ''
    ${lib.optionalString (
      (assertHasAttr "conductor section" conductorExtraOnlyConfig "conductor")
      && (assertEq "conductor auto_respond" conductorExtraOnlyConfig.conductor.auto_respond false)
      && (assertNoAttr "no enable key" conductorExtraOnlyConfig.conductor "enable")
    ) ""}
    echo "conductor extra-only test passed" > $out
  '';

  # Worktree custom path test
  worktree-custom-path = pkgs.runCommand "test-worktree-custom-path" { } ''
    ${lib.optionalString (
      (assertHasAttr "worktree section" worktreeCustomConfig "worktree")
      && (assertEq "custom default_location" worktreeCustomConfig.worktree.default_location "/tmp/worktrees")
    ) ""}
    echo "worktree custom path test passed" > $out
  '';

  # skillSources symlink generation test
  skill-sources = pkgs.runCommand "test-skill-sources" { } ''
    ${lib.optionalString (
      (assertHasAttr "pool entry" skillSourcesConfig.home.file ".agent-deck/skills/pool/linkding")
      && (assertHasAttr "config still present" skillSourcesConfig.home.file ".agent-deck/config.toml")
    ) ""}
    echo "skill sources test passed" > $out
  '';

  # Empty skillSources test (no pool entries)
  skill-sources-empty = pkgs.runCommand "test-skill-sources-empty" { } ''
    ${lib.optionalString (
      (assertNoAttr "no pool entries" emptySkillSourcesConfig.home.file ".agent-deck/skills/pool/linkding")
      && (assertHasAttr "config still present" emptySkillSourcesConfig.home.file ".agent-deck/config.toml")
    ) ""}
    echo "skill sources empty test passed" > $out
  '';
}
