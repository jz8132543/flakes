{
  config,
  pkgs,
  ...
}:
{
  services.minio = {
    enable = true;
    listenAddress = "127.0.0.1:${toString config.ports.minio}";
    consoleAddress = "127.0.0.1:${toString config.ports.minio-console}";
    rootCredentialsFile = config.sops.templates."minio-root-credentials".path;
    # dataDir = ["/mnt/minio/data"];
    # configDir = "/mnt/minio/config";
  };
  sops.secrets."minio/user" = {
    restartUnits = [ "minio.service" ];
  };
  sops.secrets."minio/password" = {
    restartUnits = [ "minio.service" ];
  };
  sops.templates."minio-root-credentials".content = ''
    MINIO_ROOT_USER=${config.sops.placeholder."minio/user"}
    MINIO_ROOT_PASSWORD=${config.sops.placeholder."minio/password"}
    MINIO_UPDATE=off
  '';
  services.traefik.proxies = {
    minio = {
      rule = "Host(`minio.${config.networking.domain}`)";
      target = "http://localhost:${toString config.ports.minio}";
    };
    minio-console = {
      rule = "Host(`minio-console.${config.networking.domain}`)";
      target = "http://localhost:${toString config.ports.minio-console}";
    };
  };
  environment.systemPackages = [
    config.services.minio.package
    pkgs.minio-client
  ];
}
