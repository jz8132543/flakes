{ config, lib, ... }:

{
  sops.secrets.s3_credentials = {
    format = "binary";
    mode = "0444";
    sopsFile = config.sops.secretsDir + /s3_credentials.keytab;
  };
  nix = lib.mkIf (!config.environment.China.enable) {
    settings.substituters = [ "s3://nix?endpoint=g5s3.ph11.idrivee2-11.com" ];
    settings.trusted-public-keys = [
      "dora-1:Jwud5q69IwWld/IqXW6nwBDx5s8WtsKpim+N5v+8fiE="
    ];
  };
}
