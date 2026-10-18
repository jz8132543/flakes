{
  inputs,
  config,
  lib,
  self,
  ...
}:
{
  imports = [
  ];
  # Minimal registry: only register this flake to avoid evaluating all inputs
  # during system evaluation.
  nix.registry = lib.mkForce {
    self = {
      flake = self;
      to = {
        type = "github";
        owner = "jz8132543";
        repo = "flakes";
        rev = self.rev or "main";
      };
    };
  };
  nix = {
    optimise.automatic = true;
    channel.enable = false;
    gc = {
      automatic = true;
      # dates = "weekly"; # default: "03:15"
      options = "--delete-older-than 7d";
    };
    settings = {
      connect-timeout = 10;
      stalled-download-timeout = 30;
      allow-import-from-derivation = true;
      accept-flake-config = true;
      nix-path = [
        "nixpkgs=${inputs.nixpkgs}"
        # "nixpkgs-stable=${inputs.release.outPath}"
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
      min-free = 3500 * 1024 * 1024; # 3.5 GiB: trigger auto-GC when free space drops below 3.5G
      max-free = 5000 * 1024 * 1024; # 5.0 GiB: stop GC when free space recovers to 5.0G
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
      protocol = "ssh-ng";
      write = true;
    };
    # settings.trusted-users = ["nix-ssh"];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
