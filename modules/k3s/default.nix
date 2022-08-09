{ config, ... }: 

{
  imports = [
    ./nginx.nix
    ./server.nix
    #./agent.nix
  ];
  sops.secrets.k3s-server-token.sopsFile = config.sops.secretsDir + /k3s.yml;
}
