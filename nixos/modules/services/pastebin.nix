{
  config,
  pkgs,
  ...
}:
{
  # services.nginx.virtualHosts."pb.*" = {
  #   forceSSL = true;
  #   inherit (config.security.acme.tfCerts."li7g_com".nginxSettings) sslCertificate sslCertificateKey;
  #   locations."/" = {
  #     proxyPass = "http://127.0.0.1:${toString config.ports.pastebin}";
  #     extraConfig = ''
  #       add_header Cache-Control "public, no-cache";
  #     '';
  #   };
  #   extraConfig = ''
  #     client_max_body_size 25M;
  #   '';
  # };
  systemd.services.pastebin = {
    script = ''
      # export AWS_ACCESS_KEY_ID=$(cat "$CREDENTIALS_DIRECTORY/key-id")
      # export AWS_SECRET_ACCESS_KEY=$(cat "$CREDENTIALS_DIRECTORY/access-key")
      ${pkgs.pastebin}/bin/pastebin \
        # --endpoint-host minio.li7g.com \
        # --bucket pastebin \
        --addressing-style path \
        --port "${toString config.ports.pastebin}"
    '';
    serviceConfig = {
      DynamicUser = true;
      # LoadCredential = [
      #   "key-id:${config.sops.secrets."minio_pastebin_key_id".path}"
      #   "access-key:${config.sops.secrets."minio_pastebin_access_key".path}"
      # ];
    };
    wantedBy = [ "multi-user.target" ];
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      atuin = {
        rule = "Host(`pb.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "pastebin";
      };
    };
    services = {
      pastebin.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.pastebin}"; } ];
      };
    };
  };
}
