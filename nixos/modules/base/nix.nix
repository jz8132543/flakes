{
  inputs,
  config,
  ...
}: {
  nix = {
    optimise.automatic = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings = {
      nix-path = ["nixpkgs=${inputs.nixpkgs}"];
      experimental-features = ["nix-command" "flakes" "auto-allocate-uids" "cgroups" "repl-flake"];
      system-features = ["nixos-test" "benchmark" "big-parallel" "kvm"];
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
      # protocol = "ssh-ng";
      protocol = "ssh";
      write = true;
    };
    settings.trusted-users = ["nix-ssh"];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
