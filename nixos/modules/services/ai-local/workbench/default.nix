{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.local-llm.workbench;
  system = pkgs.stdenv.hostPlatform.system;
  jailedOmp = inputs.jailed-agents.lib.${system}.makeJailedOmp {
    pkg = inputs.omp-flake.packages.${system}.default;
    extraPkgs = with pkgs; [
      git
      python3
      uv
      nix
      nixfmt
      statix
      deadnix
      nixd
      pandoc
      typst
    ];
    enableNix = true;
  };
  omp = pkgs.writeShellScriptBin "omp" ''
    exec ${jailedOmp}/bin/jailed-omp "$@"
  '';
  paseoPackage = inputs.paseo.packages.${system}.default.overrideAttrs (old: {
    preBuild = (old.preBuild or "") + ''
      npm run postinstall
    '';
  });
in
{
  imports = [ inputs.paseo.nixosModules.default ];

  options.services.local-llm.workbench.enable = lib.mkEnableOption "general local AI agents";

  config = lib.mkIf cfg.enable {
    sops.secrets."openai_api_key" = { };

    sops.templates."hermes-provider.env" = {
      owner = "tippy";
      group = "users";
      mode = "0400";
      content = ''
        OPENAI_API_KEY=${config.sops.placeholder."openai_api_key"}
      '';
    };

    environment.systemPackages = [
      omp
    ];

    environment.global-persistence.user.directories = [ ".omp" ];

    # Paseo sessions run as tippy, whose account has passwordless sudo. The
    # daemon therefore remains loopback-only and is not exposed to other clients.
    services.paseo = {
      package = lib.mkForce paseoPackage;
      user = "tippy";
      group = "users";
      dataDir = "/var/lib/paseo";
      port = config.ports.paseo;
      listenAddress = "127.0.0.1";
      openFirewall = false;
      hostnames = [ ];
      relay.enable = false;
      inheritUserEnvironment = true;
      settings = {
        daemon.listen = "127.0.0.1:${toString config.ports.paseo}";
        features.webUi.enabled = true;
        agents.providers = {
          claude.enabled = false;
          codex.enabled = false;
          copilot.enabled = false;
          opencode.enabled = false;
          pi.enabled = false;
          omp = {
            enabled = true;
            command = [ "omp" ];
          };
        };
      };
    };

    systemd.services.paseo = {
      after = [
        "home-manager-tippy.service"
        "home-tippy-.omp.mount"
      ];
      requires = [
        "home-manager-tippy.service"
        "home-tippy-.omp.mount"
      ];
      unitConfig.RequiresMountsFor = [ "/var/lib/paseo" ];
    };
  };
}
