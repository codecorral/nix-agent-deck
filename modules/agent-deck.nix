{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption mkIf types filterAttrs mapAttrs' nameValuePair recursiveUpdate;
  cfg = config.programs.agent-deck;
  tomlFormat = pkgs.formats.toml { };

  # D7: Explicit camelCase-to-snake_case mapping table for section names
  sectionNameMap = {
    globalSearch = "global_search";
    mcpPool = "mcp_pool";
  };

  # D7: Explicit camelCase-to-snake_case mapping table for key names
  keyNameMap = {
    envFiles = "env_files";
    initScript = "init_script";
    ignoreMissingEnvFiles = "ignore_missing_env_files";
    configDir = "config_dir";
    dangerousMode = "dangerous_mode";
    allowDangerousMode = "allow_dangerous_mode";
    envFile = "env_file";
    yoloMode = "yolo_mode";
    defaultEnabled = "default_enabled";
    defaultImage = "default_image";
    cpuLimit = "cpu_limit";
    memoryLimit = "memory_limit";
    mountSsh = "mount_ssh";
    autoCleanup = "auto_cleanup";
    volumeIgnores = "volume_ignores";
    maxSizeMb = "max_size_mb";
    maxLines = "max_lines";
    removeOrphans = "remove_orphans";
    autoUpdate = "auto_update";
    checkEnabled = "check_enabled";
    checkIntervalHours = "check_interval_hours";
    notifyInCli = "notify_in_cli";
    memoryLimitMb = "memory_limit_mb";
    recentDays = "recent_days";
    indexRateLimit = "index_rate_limit";
    autoStart = "auto_start";
    poolAll = "pool_all";
    excludeMcps = "exclude_mcps";
    fallbackToStdio = "fallback_to_stdio";
    showPoolStatus = "show_pool_status";
    defaultTool = "default_tool";
    defaultLocation = "default_location";
  };

  # Map a key name using the explicit table, passthrough if not mapped
  mapKey = name: keyNameMap.${name} or name;

  # Map a section name using the explicit table, passthrough if not mapped
  mapSection = name: sectionNameMap.${name} or name;

  # Convert an attrset's keys from camelCase to snake_case using the mapping table
  mapKeys = attrs:
    mapAttrs' (name: value: nameValuePair (mapKey name) value) attrs;

  # Remove null values from an attrset
  removeNulls = attrs:
    filterAttrs (_: v: v != null) attrs;

  # Build a section: map keys, remove nulls, return null if empty
  buildSection = attrs:
    let mapped = mapKeys (removeNulls attrs);
    in if mapped == { } then null else mapped;

  # Build the complete config attrset
  buildConfig = let
    topLevel = removeNulls {
      default_tool = cfg.defaultTool;
    };

    sections = removeNulls (mapAttrs' (name: value:
      nameValuePair (mapSection name) value
    ) (removeNulls {
      shell = buildSection {
        inherit (cfg.shell) envFiles initScript ignoreMissingEnvFiles;
      };
      claude = buildSection {
        inherit (cfg.claude) configDir dangerousMode allowDangerousMode envFile;
      };
      codex = buildSection {
        inherit (cfg.codex) yoloMode;
      };
      docker = buildSection {
        inherit (cfg.docker) defaultEnabled defaultImage cpuLimit memoryLimit mountSsh autoCleanup environment volumeIgnores;
      };
      logs = buildSection {
        inherit (cfg.logs) maxSizeMb maxLines removeOrphans;
      };
      updates = buildSection {
        inherit (cfg.updates) autoUpdate checkEnabled checkIntervalHours notifyInCli;
      };
      globalSearch = buildSection {
        inherit (cfg.globalSearch) enabled tier memoryLimitMb recentDays indexRateLimit;
      };
      mcpPool = buildSection {
        inherit (cfg.mcpPool) enabled autoStart poolAll excludeMcps fallbackToStdio showPoolStatus;
      };
      worktree = buildSection {
        inherit (cfg.worktree) defaultLocation;
      };
    }));

    # MCP definitions pass through as-is (already snake_case from user)
    mcpSection = if cfg.mcps != { } then { mcps = cfg.mcps; } else { };

    # Tool definitions pass through as-is
    toolSection = if cfg.tools != { } then { tools = cfg.tools; } else { };

    # Profile definitions need key mapping for nested claude options
    profileSection = let
      mappedProfiles = mapAttrs' (profileName: profileCfg:
        nameValuePair profileName (removeNulls {
          claude = buildSection {
            inherit (profileCfg.claude) configDir;
          };
        })
      ) cfg.profiles;
      nonEmpty = filterAttrs (_: v: v != { }) mappedProfiles;
    in if nonEmpty != { } then { profiles = nonEmpty; } else { };

  in recursiveUpdate (topLevel // sections // mcpSection // toolSection // profileSection) cfg.extraConfig;

  # Profile submodule type
  profileModule = types.submodule {
    options.claude = {
      configDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Claude config directory override for this profile.";
      };
    };
  };

in
{
  options.programs.agent-deck = {
    enable = mkEnableOption "agent-deck configuration management";

    defaultTool = mkOption {
      type = types.nullOr types.str;
      default = "claude";
      description = "Default AI tool to use (e.g., \"claude\", \"codex\"). Set to null to omit.";
    };

    # 2.2: Shell section
    shell = {
      envFiles = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "List of env files to source in session shells.";
      };
      initScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Shell init script to run in session shells.";
      };
      ignoreMissingEnvFiles = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether to ignore missing env files.";
      };
    };

    # 2.3: Claude section
    claude = {
      configDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Claude config directory path.";
      };
      dangerousMode = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable dangerous mode for Claude.";
      };
      allowDangerousMode = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Allow dangerous mode for Claude.";
      };
      envFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to env file for Claude API keys.";
      };
    };

    # 2.4: Codex section
    codex = {
      yoloMode = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable YOLO mode for Codex.";
      };
    };

    # 2.5: Docker section
    docker = {
      defaultEnabled = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable Docker sandbox by default.";
      };
      defaultImage = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default Docker image for sandboxes.";
      };
      cpuLimit = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "CPU limit for Docker containers.";
      };
      memoryLimit = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Memory limit for Docker containers.";
      };
      mountSsh = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Mount SSH keys into Docker containers.";
      };
      autoCleanup = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Auto-cleanup Docker containers.";
      };
      environment = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Environment variables for Docker containers.";
      };
      volumeIgnores = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Volume paths to ignore in Docker mounts.";
      };
    };

    # 2.6: Logs section
    logs = {
      maxSizeMb = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum log size in MB.";
      };
      maxLines = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum number of log lines.";
      };
      removeOrphans = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Remove orphaned log files.";
      };
    };

    # 2.7: Updates section
    updates = {
      autoUpdate = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable auto-updates.";
      };
      checkEnabled = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable update checks.";
      };
      checkIntervalHours = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Hours between update checks.";
      };
      notifyInCli = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show update notifications in CLI.";
      };
    };

    # 2.8: Global search section
    globalSearch = {
      enabled = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable global search.";
      };
      tier = mkOption {
        type = types.nullOr (types.enum [ "auto" "instant" "balanced" ]);
        default = null;
        description = "Search tier mode.";
      };
      memoryLimitMb = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Memory limit for search in MB.";
      };
      recentDays = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Number of recent days to search.";
      };
      indexRateLimit = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Index rate limit.";
      };
    };

    # 2.9: MCP pool section
    mcpPool = {
      enabled = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable MCP connection pooling.";
      };
      autoStart = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Auto-start MCP pool.";
      };
      poolAll = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Pool all MCP connections.";
      };
      excludeMcps = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "MCPs to exclude from pooling.";
      };
      fallbackToStdio = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Fall back to STDIO if pool fails.";
      };
      showPoolStatus = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show pool status in CLI.";
      };
    };

    # Worktree section
    worktree = {
      defaultLocation = mkOption {
        type = types.nullOr (types.either (types.enum [ "sibling" "subdirectory" ]) types.str);
        default = null;
        description = ''Default worktree location: "sibling", "subdirectory", or a custom path.'';
      };
    };

    # 2.10: MCP definitions (freeform)
    mcps = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      description = "MCP server definitions. Each key is an MCP name, value is its configuration.";
    };

    # 2.11: Tool definitions (freeform)
    tools = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      description = "Custom tool definitions. Each key is a tool name, value is its configuration.";
    };

    # 2.12: Profiles
    profiles = mkOption {
      type = types.attrsOf profileModule;
      default = { };
      description = "Profile-level overrides. Each key is a profile name.";
    };

    # 2.13: Extra config escape hatch
    extraConfig = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra configuration merged into generated TOML. Use for options not covered by typed options.";
    };
  };

  config = mkIf cfg.enable {
    home.file.".agent-deck/config.toml".source =
      tomlFormat.generate "agent-deck-config.toml" buildConfig;
  };
}
