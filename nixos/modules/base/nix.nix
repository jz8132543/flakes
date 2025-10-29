{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    # TODO switch to lixFromNixpkgs once 2.93.2 is available
    inputs.lix-module.nixosModules.default
    # inputs.lix-module.nixosModules.lixFromNixpkgs
  ];
  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    optimise.automatic = true;
    channel.enable = false;
    gc = {
      automatic = true;
      # dates = "weekly"; # default: "03:15"
      options = "--delete-older-than 7d";
    };
    settings = {
      allow-import-from-derivation = true;
      nix-path = [
        "nixpkgs=${inputs.nixpkgs}"
        "nixpkgs-master=${inputs.latest.outPath}"
        "nixpkgs-stable=${inputs.release.outPath}"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
        "auto-allocate-uids"
        "cgroups"
      ];
      system-features = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
      auto-allocate-uids = true;
      use-cgroups = true;
      auto-optimise-store = true;
      warn-dirty = false;
      min-free = 1024 * 1024 * 1024; # bytes
      sandbox = true;
      keep-outputs = true;
      keep-derivations = true;
      fallback = true;
      allowed-users = [ "@users" ];
      trusted-users = [
        "root"
        "@wheel"
      ];
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
    # settings.trusted-users = ["nix-ssh"];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
