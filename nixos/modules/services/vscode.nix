{
  config,
  ...
}:
{
  # imports = [ inputs.nixos-vscode-server.nixosModules.default ];
  services.code-server = {
    enable = true;
    port = config.ports.code;
    disableUpdateCheck = true;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      code = {
        rule = "Host(`code.${config.networking.domain}`)";
        service = "code";
      };
    };
    services = {
      code.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.code}"; } ];
      };
    };
  };
}
