{
  inputs,
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  # Keep daemon settings independent of environment.variables and its package dependencies.
  gcMinFree = 1024 * 1024 * 1024;
  gcMaxFree = 30 * 1024 * 1024 * 1024;
in
{
  # Bytes, exported for inspection and consumed when evaluating nix.conf/scripts.
  # Shell exports do not change a running daemon; edit here and deploy instead.
  environment.variables = {
    NIX_GC_A = toString (4 * 1024 * 1024 * 1024); # A: prune all old generations below 4 GiB after deployment.
    NIX_GC_B = toString gcMinFree; # B: trigger emergency auto-GC below 1 GiB during imports/builds.
    NIX_GC_C = toString gcMaxFree; # C: aim for 30 GiB free; stop when collectable garbage is exhausted.
  };

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
    package = pkgs.nixVersions.nix_2_35;
    settings = {
      connect-timeout = 2;
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
      min-free = gcMinFree;
      max-free = gcMaxFree;
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
