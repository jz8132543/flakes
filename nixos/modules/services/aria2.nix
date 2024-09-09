{
  lib,
  pkgs,
  ...
}:
{
  services.aria2 = {
    enable = true;
    rpcSecretFile = "/run/credentials/aria2.service/rpcSecretFile";
    settings = {
      max-connection-per-server = 16;
      split = 64;
      min-split-size = "4M";
      http-accept-gzip = true;
      content-disposition-default-utf8 = true;
      dht-entry-point = "dht.transmissionbt.com:6881";
      dht-entry-point6 = "dht.transmissionbt.com:6881";
      bt-force-encryption = true;
    };
    # extraArguments = lib.concatStringsSep " " [
    #   "--max-connection-per-server=16"
    #   "--split=64"
    #   "--min-split-size=4M"
    #   "--http-accept-gzip=true"
    #   "--content-disposition-default-utf8=true"
    #   "--dht-entry-point=dht.transmissionbt.com:6881"
    #   "--dht-entry-point6=dht.transmissionbt.com:6881"
    #   "--bt-force-encryption=true"
    #   # "--bt-tracker=${builtins.readFile pkgs.trackerslist}"
    # ];
  };
  systemd.services.aria2.serviceConfig = {
    LoadCredential = lib.mkForce [
      "rpcSecretFile:${pkgs.writeText "secret1" "aria2rpc"}"
    ];
  };
  systemd.tmpfiles.rules = [
    "f '/var/lib/aria2/aria2.conf' 0666 aria2 aria2"
    "d '/var/lib/aria2/' 0777 aria2 aria2"
  ];
}
