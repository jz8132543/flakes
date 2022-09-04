{
  nix = {
    settings.substituters = [ "s3://nix?endpoint=g5s3.ph11.idrivee2-11.com" ];
    settings.trusted-public-keys = [
      "dora-1:Jwud5q69IwWld/IqXW6nwBDx5s8WtsKpim+N5v+8fiE="
    ];
  };
}
