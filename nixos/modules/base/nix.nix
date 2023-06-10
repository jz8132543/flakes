{
  inputs,
  config,
  ...
}: {
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
      warn-dirty = false;
    };
    sshServe = {
      enable = true;
      keys = [
        config.lib.self.data.ssh.i
        config.lib.self.data.ssh.hydra
      ];
      protocol = "ssh";
      write = true;
    };
    settings.trusted-users = ["nix-ssh"];
  };
}
