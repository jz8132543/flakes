{inputs, ...}: {
  nix = {
    nrBuildUsers = 0;
    optimise.automatic = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    settings = {
      nix-path = ["nixpkgs=${inputs.nixpkgs}"];
      experimental-features = ["nix-command" "flakes" "auto-allocate-uids" "cgroups"];
      auto-allocate-uids = true;
      use-cgroups = true;
      auto-optimise-store = true;
    };
  };
  nixpkgs.config.allowUnfree = true;
}
