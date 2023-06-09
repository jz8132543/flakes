{config, ...}: {
  nix.extraOptions = ''
    !include ${config.sops.templates."nix-extra-config".path}
  '';
  nix.checkConfig = false;
  sops.templates."nix-extra-config" = {
    content = ''
      access-tokens = github.com=${config.sops.placeholder."hydra/github-token"}
    '';
    group = config.users.groups.nix-access-tokens.name;
    mode = "0440";
  };
  users.groups.nix-access-tokens.gid = config.ids.gids.nix-access-tokens;
  sops.secrets."hydra/github-token" = {
    restartUnits = ["nix-daemon.service"];
  };
}
