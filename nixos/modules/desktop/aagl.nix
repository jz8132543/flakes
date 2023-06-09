{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.aagl-gtk-on-nix.nixosModules.default
  ];

  programs.anime-game-launcher.enable = true;

  environment.systemPackages = with pkgs; [
    dxvk
    proton-caller
  ];

  nix.settings = {
    substituters = ["https://ezkea.cachix.org"];
    trusted-public-keys = ["ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="];
  };
}