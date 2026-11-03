{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.openhands-agent-canvas;
  bootstrapConfig = pkgs.writeText "openhands-bootstrap.json" (
    builtins.toJSON {
      api_base = "http://127.0.0.1:${toString cfg.port}";
      key_file = "${cfg.dataDir}/backend-key";
      marker_file = "${cfg.dataDir}/bootstrap-v1.json";
      gateway_base = cfg.gatewayBaseUrl;
      gateway_key_file = config.sops.secrets.${cfg.gatewayApiKeySecret}.path;
      profiles = {
        default = "devin/gpt-6-1-sol";
        fast = "devin/deepseek-v4-flash";
        reasoning = "claude-opus-4-6";
      };
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
          mcp_config = {
            web-fetch = {
              transport = "stdio";
              command = "uvx";
              args = [ "mcp-server-fetch==2026.10.28" ];
              description = "Read public webpages and convert their content to Markdown.";
            };
            time = {
              transport = "stdio";
              command = "uvx";
              args = [
                "mcp-server-time==2026.10.28"
                "--local-timezone=Asia/Shanghai"
              ];
              description = "Current time and timezone conversion.";
            };
            sequential-thinking = {
              transport = "stdio";
              command = "npx";
              args = [
                "--yes"
                "@modelcontextprotocol/server-sequential-thinking@2.0.0"
              ];
              description = "Structured, revisable reasoning for complex tasks.";
              env.DISABLE_THOUGHT_LOGGING = "true";
            };
          };
        };
        conversation_settings_diff = {
          confirmation_mode = true;
          security_analyzer = null;
          max_iterations = 100;
          container_browser = true;
        };
      };
      drafts = [
        {
          name = "Daily developer research brief";
          prompt = "Read the public OpenHands releases and relevant developer-tool announcements. Write a concise Chinese research brief with source URLs under /projects/research. Do not publish, send messages, or change deployments.";
          schedule = "0 9 * * *";
        }
        {
          name = "Workspace code review";
          prompt = "Review repositories explicitly placed under /projects. Report concrete correctness and security findings with file references. Do not edit, commit, push, merge, or access unrelated paths.";
          schedule = "0 19 * * 1-5";
        }
        {
          name = "Browser QA report";
          prompt = "Ask for the project and test URL first. Use the browser to test its main user journeys and desktop/mobile layouts, then write a reproducible QA report under /projects. Do not submit purchases, send messages, or change external data.";
          schedule = "0 10 * * 1";
        }
      ];
    }
  );
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
  ];

  options.services.ai.openhands-agent-canvas = {
    enable = lib.mkEnableOption "OpenHands Agent Canvas";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "openhands.${config.networking.domain}";
      description = "Authenticated HTTPS domain for the single-user Canvas.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/openhands/agent-canvas@sha256:f96a67b825fae3e8a0587516e48216a68913eb3aaf7f069ec2a68dfe643bbdce";
      description = "Container image for OpenHands Agent Canvas.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.openhands-agent-canvas;
      description = "Localhost port for OpenHands Agent Canvas.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openhands-agent-canvas";
      description = "Directory containing the agent's mounted project workspace.";
    };

    gatewayBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cpa.${config.networking.domain}/v1";
      description = "OpenAI-compatible API endpoint used by the initial LLM profiles.";
    };

    gatewayApiKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "openai_api_key";
      description = "SOPS secret supplying the initial model-provider key.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.gatewayApiKeySecret} = { };

    systemd.services.openhands-backend-key = {
      description = "Initialize the persistent OpenHands backend credentials";
      before = [ "podman-openhands-agent-canvas.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      path = [
        pkgs.openssl
        pkgs.podman
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        install -d -m 0750 -o root -g users ${lib.escapeShellArg cfg.dataDir}
        if [ ! -s ${lib.escapeShellArg "${cfg.dataDir}/backend-key"} ]; then
          volume="$(podman volume inspect openhands-data --format '{{.Mountpoint}}' 2>/dev/null || true)"
          if [ -n "$volume" ] && [ -s "$volume/agent-canvas/api-key.txt" ]; then
            install -m 0600 "$volume/agent-canvas/api-key.txt" ${lib.escapeShellArg "${cfg.dataDir}/backend-key"}
          else
            openssl rand -hex 32 > ${lib.escapeShellArg "${cfg.dataDir}/backend-key"}
          fi
        fi
        key="$(tr -d '\r\n' < ${lib.escapeShellArg "${cfg.dataDir}/backend-key"})"
        if [[ ! "$key" =~ ^[A-Za-z0-9_-]{24,}$ ]]; then
          exit 1
        fi
        # The launcher and SDK use different names; both must authenticate.
        printf 'LOCAL_BACKEND_API_KEY=%s\nOH_SESSION_API_KEYS_0=%s\n' "$key" "$key" \
          > ${lib.escapeShellArg "${cfg.dataDir}/backend.env"}
      '';
    };

    virtualisation.oci-containers.containers.openhands-agent-canvas = {
      inherit (cfg) image;
      ports = [ "127.0.0.1:${toString cfg.port}:8000" ];
      environmentFiles = [ "${cfg.dataDir}/backend.env" ];
      environment = {
        AUTOMATION_BASE_URL = "https://${cfg.domain}";
        OH_ENABLE_VSCODE = "false";
        UV_CACHE_DIR = "/home/openhands/.openhands/cache/uv";
        NPM_CONFIG_CACHE = "/home/openhands/.openhands/cache/npm";
      };
      volumes = [
        "openhands-data:/home/openhands/.openhands"
        "${cfg.dataDir}/projects:/projects"
      ];
      labels."io.containers.autoupdate" = "disabled";
      log-driver = "journald";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root users -"
      # The image uses UID 10001; the users group can also manage project files.
      "d ${cfg.dataDir}/projects 2770 10001 users -"
    ];

    systemd.services.podman-openhands-agent-canvas = {
      after = [
        "systemd-tmpfiles-setup.service"
        "openhands-backend-key.service"
      ];
      requires = [
        "systemd-tmpfiles-setup.service"
        "openhands-backend-key.service"
      ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        "/var/lib/containers"
      ];
    };

    services.traefik.proxies.openhands-agent-canvas = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
      entryPoints = [ "https" ];
      middlewares = [
        "auth"
        "openhands-security"
      ];
    };
    services.traefik.dynamicConfigOptions.http.middlewares.openhands-security.headers = {
      contentTypeNosniff = true;
      referrerPolicy = "no-referrer";
      stsSeconds = 31536000;
      customResponseHeaders.Cache-Control = "no-store";
    };

    systemd.services.openhands-bootstrap = {
      description = "Seed OpenHands tools, model profiles, workspace, and inactive automation drafts";
      wantedBy = [ "multi-user.target" ];
      after = [
        "podman-openhands-agent-canvas.service"
        "openhands-backend-key.service"
        "sops-install-secrets.service"
      ];
      requires = [
        "podman-openhands-agent-canvas.service"
        "openhands-backend-key.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ExecStart = "${pkgs.python3}/bin/python3 ${./openhands-bootstrap.py} ${bootstrapConfig}";
        Restart = "on-failure";
        RestartSec = "15s";
        TimeoutStartSec = "5min";
      };
    };

    services.restic.backups.borgbase.paths = [
      cfg.dataDir
      "/var/lib/containers/storage/volumes/openhands-data/_data"
    ];
  };
}
