{ config, ... }:
let
  cfg = config.modules.services.k3s;
in
with lib; {
  options.modules.services.k3s = {
    enable = _.mkBoolOpt false;
  };
  imports = mkIf cfg.enable [
    ./nginx.nix
    ./server.nix
    #./agent.nix
  ];
  sops.secrets.k3s-server-token.sopsFile = config.sops.secretsDir + /k3s.yml;
}
