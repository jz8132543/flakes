{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.ai.openhands;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.ai.openhands = {
    enable = lib.mkEnableOption "OpenHands autonomous agent workspace";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "openhands.${config.networking.domain}";
      description = "Authenticated HTTPS domain for OpenHands.";
    };

    aliasDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional HTTPS hostnames redirected to the primary OpenHands domain.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/openhands/agent-canvas@sha256:f96a67b825fae3e8a0587516e48216a68913eb3aaf7f069ec2a68dfe643bbdce";
      description = "Pinned OpenHands Agent Canvas image.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openhands";
      description = "Persistent root for OpenHands state and user-managed assets.";
    };

    gatewayBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${config.services.new-api.domain}/v1";
      description = "OpenAI-compatible model gateway URL.";
    };

    network = {
      enable = lib.mkEnableOption "a dedicated Podman bridge with OpenHands-specific egress policy";
      publicInterface = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[a-zA-Z0-9_.-]{1,15}");
        default = null;
        description = "Underlay interface for public IPv4 HTTP(S) and DNS. Null denies forwarded egress.";
      };
      gatewayAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.231.48.1";
        readOnly = true;
        description = "Host address of the dedicated OpenHands bridge.";
      };
    };

    gatewayApiKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "openai_api_key";
      description = "Existing SOPS OpenAI-compatible API key shared with New-API clients.";
    };

    backendApiKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "openhands/backend_api_key";
      description = "SOPS key for the OpenHands session API, shared only with trusted clients.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        default = "gpt-6.1-sol";
        fast = "gpt-5.6-sol";
        reasoning = "gpt-6.2-sol";
      };
      description = "Named OpenAI-compatible model profiles offered by the UI.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "OpenHands MCP server definitions, including transport-specific settings.";
    };

    mcpServerSecrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Map MCP server names to SOPS keys containing Bearer tokens.";
    };

    skillsDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/skills";
      description = "User-managed, domain-neutral SKILL.md and microagent files.";
    };

    container = {
      memoryMax = lib.mkOption {
        type = lib.types.str;
        default = "2G";
        description = "Systemd memory limit for the OpenHands web container.";
      };
      cpuQuota = lib.mkOption {
        type = lib.types.str;
        default = "200%";
        description = "CPU quota for the OpenHands web container.";
      };
      pidsLimit = lib.mkOption {
        type = lib.types.ints.positive;
        default = 256;
        description = "Maximum process count for the OpenHands web container.";
      };
      cpus = lib.mkOption {
        type = lib.types.str;
        default = "2";
        description = "Container CPU quota expressed as a Podman --cpus value.";
      };
    };

    automation.enable = lib.mkEnableOption "OpenHands scheduled automation drafts";

    oidc = {
      clientId = lib.mkOption {
        type = lib.types.str;
        default = "openhands";
        description = "Keycloak OIDC client identifier.";
      };
      clientSecretKey = lib.mkOption {
        type = lib.types.str;
        default = "openhands/oidc-secret";
        description = "SOPS key holding the Keycloak confidential-client secret.";
      };
      cookieSecretKey = lib.mkOption {
        type = lib.types.str;
        default = "openhands/oauth_cookie_secret";
        description = "SOPS key holding the oauth2-proxy cookie secret.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      ${cfg.gatewayApiKeySecret} = { };
      ${cfg.backendApiKeySecret} = { };
      ${cfg.oidc.clientSecretKey} = { };
      ${cfg.oidc.cookieSecretKey} = { };
    }
    // lib.mapAttrs' (_name: key: lib.nameValuePair key { }) cfg.mcpServerSecrets;

    sops.templates."openhands-gateway.env".content = ''
      LOCAL_BACKEND_API_KEY=${config.sops.placeholder.${cfg.backendApiKeySecret}}
      OH_SESSION_API_KEYS_0=${config.sops.placeholder.${cfg.backendApiKeySecret}}
    '';

    sops.templates."openhands-oauth2-proxy.env".content = ''
      OAUTH2_PROXY_CLIENT_SECRET=${config.sops.placeholder.${cfg.oidc.clientSecretKey}}
      OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder.${cfg.oidc.cookieSecretKey}}
    '';

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root users - -"
      "d ${cfg.dataDir}/state 0750 10001 users - -"
      "d ${cfg.dataDir}/knowledge 2770 10001 users - -"
      "d ${cfg.dataDir}/workspace 2770 10001 users - -"
      "d ${cfg.skillsDir} 2770 10001 users - -"
      "d ${cfg.dataDir}/outputs 2770 10001 users - -"
    ];

    environment.global-persistence.directories = [
      cfg.dataDir
    ]
    ++ lib.optional (cfg.skillsDir != "${cfg.dataDir}/skills") cfg.skillsDir;

    assertions = [
      {
        assertion = !(lib.elem cfg.domain cfg.aliasDomains);
        message = "OpenHands cannot redirect its primary domain to itself.";
      }
      {
        assertion =
          !(config.virtualisation.oci-containers.containers ? lobechat)
          || !(lib.elem "chat.dora.im" ([ cfg.domain ] ++ cfg.aliasDomains));
        message = "OpenHands and LobeChat cannot both serve chat.dora.im.";
      }
    ];
  };
}
