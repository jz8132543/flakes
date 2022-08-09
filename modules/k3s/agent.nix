{ config, ... }:

{
  sops.secrets.k3s-server-token.sopsFile = ../../secrets/k3s.yml;
  services.k3s = {
    enable = true;
    tokenFile = config.sops.secrets.k3s-server-token.path;
    serverAddr = "https://tyo0.dora.im:6443";
  };
}
