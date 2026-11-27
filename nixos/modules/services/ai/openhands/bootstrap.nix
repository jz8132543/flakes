{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.openhands;
  bootstrapConfig = pkgs.writeText "openhands-bootstrap.json" (
    builtins.toJSON {
      api_base = "http://127.0.0.1:${toString config.ports.openhands}";
      key_file = "session-key";
      gateway_key_file = "gateway-key";
      gateway_base = cfg.gatewayBaseUrl;
      mcp_servers = cfg.mcpServers;
      mcp_secret_files = lib.mapAttrs (name: _: "mcp-${name}") cfg.mcpServerSecrets;
      workspaces = [
        "knowledge"
        "workspace"
        "outputs"
      ];
      inherit (cfg) profiles;
      settings = {
        agent_settings_diff = {
          tools = map (name: { inherit name; }) [
            "terminal"
            "file_editor"
            "task_tracker"
            "switch_llm"
            "browser_tool_set"
            "task_tool_set"
            "glob"
            "grep"
          ];
          agent_context = {
            load_public_skills = true;
            load_user_skills = true;
            load_project_skills = true;
            load_memory = true;
          };
        };
        conversation_settings_diff = {
          confirmation_mode = true;
          max_iterations = 100;
          container_browser = true;
        };
      };
      drafts = lib.optionals cfg.automation.enable [
        {
          name = "Workspace maintenance review";
          prompt = "Review only explicitly configured workspaces for stale dependencies, failing tests, and actionable security findings. Do not modify files or contact external services.";
          schedule = "0 9 * * 1";
        }
      ];
    }
  );
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.openhands-bootstrap = {
      description = "Reconcile declarative OpenHands profiles, MCP, and skills";
      wantedBy = [ "multi-user.target" ];
      after = [
        "podman-openhands.service"
        "sops-install-secrets.service"
      ];
      requires = [
        "podman-openhands.service"
        "sops-install-secrets.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        StateDirectory = "openhands-bootstrap";
        StateDirectoryMode = "0700";
        LoadCredential = [
          "session-key:${config.sops.secrets.${cfg.backendApiKeySecret}.path}"
          "gateway-key:${config.sops.secrets.${cfg.gatewayApiKeySecret}.path}"
        ]
        ++ lib.mapAttrsToList (
          name: key: "mcp-${name}:${config.sops.secrets.${key}.path}"
        ) cfg.mcpServerSecrets;
        UMask = "0077";
        ExecStart = "${pkgs.python3}/bin/python3 ${./bootstrap.py} ${bootstrapConfig}";
        Restart = "on-failure";
        RestartSec = "15s";
        TimeoutStartSec = "5min";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}
