{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  options.services.ai-openclaw = {
    enable = lib.mkEnableOption "OpenClaw with official nix-openclaw home-manager module";
  };

  config = lib.mkIf config.services.ai-openclaw.enable {
    # Generate Environment file securely via SOPS templates
    sops.templates."openclaw-env".content = ''
      OPENCLAW_TELEGRAM_BOT_TOKEN=''${config.sops.placeholder."alertmanager/telegram_bot"}
      OPENCLAW_MODEL_PROVIDER=github-copilot
    '';

    home-manager.users.tippy = {
      imports = [ inputs.openclaw-nix.homeManagerModules.openclaw ];

      home.packages = [ inputs.openclaw-nix.packages.${pkgs.system}.openclaw ];

      programs.openclaw = {
        enable = true;
        package = inputs.openclaw-nix.packages.${pkgs.system}.openclaw-gateway;

        # Core API Configuration
        config = {
          host = "127.0.0.1";
          port = 3030;
          auth = {
            enabled = true;
            tokenFile = "/var/lib/openclaw/auth-token";
          };
          tools = {
            security = "allowlist";
            allowlist = [
              "read"
              "write"
              "edit"
              "web_search"
              "web_fetch"
              "message"
              "tts"
            ];
          };
        };

        # Native Plugin Integration via bundledPlugins DSL & standard env matching
        bundledPlugins = {
          summarize.enable = true; # Summarize web pages, PDFs, videos
          peekaboo.enable = true; # Take screenshots
          poltergeist.enable = false; # Control your macOS UI
          sag.enable = false; # Text-to-speech
          camsnap.enable = false; # Camera snapshots
          gogcli.enable = false; # Google Calendar
          goplaces.enable = false; # Google Places API
          bird.enable = false; # Twitter/X
          sonoscli.enable = false; # Sonos control
          imsg.enable = false; # iMessage

          # This assumes there's a telegram plugin in catalog. If not it will map custom plugins below.
          # telegram = {
          #   enable = true;
          #   config.env.TELEGRAM_BOT_TOKEN = config.sops.templates."openclaw-env".path;
          # };
        };

        # Custom Third Party Plugins per standard URL
        customPlugins = [
          {
            source = "https://github.com/jamesdwilson/Sh4d0wDB";
          }
          {
            source = "https://github.com/joshuaswarren/openclaw-tactician";
          }
          {
            source = "https://github.com/Skyzi000/openclaw-open-webui-channels"; # TG Plugin functionally
            config.env.TELEGRAM_BOT_TOKEN = config.sops.templates."openclaw-env".path;
          }
        ];
      };
    };

    # Set up pre-requisites since HM won't create /var/lib automatically like NixOS module does
    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw 0750 tippy users -"
    ];

    # Auto-generate auth token for the user if it doesn't exist
    systemd.services.openclaw-auth-generator = {
      description = "Generate OpenClaw Gateway Auth Token";
      wantedBy = [ "multi-user.target" ];
      before = [ "home-manager-tippy.service" ]; # Run before HM to ensure token exists before OpenClaw potentially boots
      serviceConfig = {
        Type = "oneshot";
        User = "tippy";
        ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f /var/lib/openclaw/auth-token ]; then ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/openclaw/auth-token; chmod 600 /var/lib/openclaw/auth-token; fi'";
      };
    };

    # Reverse Proxy
    services.traefik.proxies = {
      openclaw = {
        rule = "Host(`claw.''${config.networking.domain}`)";
        target = "http://127.0.0.1:3030";
        middlewares = [ "auth" ]; # Force Traefik Basic Auth for the UI
      };
    };

    # Persistence definition for system-level NixOS scope
    environment.global-persistence = {
      directories = [
        "/var/lib/openclaw"
      ];
    };
  };
}
