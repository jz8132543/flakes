{
  pkgs,
  inputs,
  ...
}: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  home.packages = with pkgs; [
    inputs.devenv.packages.${pkgs.system}.devenv
  ];
}
