{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-index-database.hmModules.nix-index
  ];
  home.sessionPath = [ "$HOME/.local/bin" ];

  # programs.home-manager.enable = true;
  # https://github.com/nix-community/home-manager/issues/3211
  home.packages = [ pkgs.home-manager ];
}
