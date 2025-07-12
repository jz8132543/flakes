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
    hashedPassword = "$argon2i$v=19$m=4096,t=3,p=1$bElKaGtpd1RnMEpOK3psNmpyU2dwcDFHU0U0PQ$ZCgtKICfKUwPFsChiEIqcmVDRGafF1JEZAN9Fu5klQA";
    #auth = "";
  };

  systemd.services.code-server.serviceConfig.EnvironmentFile = [
    config.sops.templates."code-server-environment".path
  ];
  sops.templates."code-server-environment" = {
    content = ''
      # CODER_OIDC_ISSUER_URL="https://sso.dora.im/realms/users"
      # CODER_OIDC_CLIENT_ID="code-server"
      # CODER_OIDC_CLIENT_SECRET=${config.sops.placeholder."code-server/oidc-secret"}
      # CODER_OIDC_SCOPES="openid,profile,email"
      # CODER_DISABLE_PASSWORD_AUTH=true
      HASHED_PASSWORD=${config.sops.placeholder."code-server/hashed-password"}
    '';
  };
  sops.secrets = {
    "code-server/oidc-secret" = { };
    "code-server/hashed-password" = { };
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
  environment.global-persistence.user = {
    directories = [
      ".local/share/code-server"
    ];
  };

}
