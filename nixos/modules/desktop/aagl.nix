{inputs, ...}: {
  imports = [
    inputs.aagl-gtk-on-nix.nixosModules.default
  ];

  programs.an-anime-game-launcher.enable = true;

  nix.settings = {
    substituters = ["https://ezkea.cachix.org"];
    trusted-public-keys = ["ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="];
  };
}
