{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
  ];
  # Minimal registry: only register this flake to avoid evaluating all inputs
  # during system evaluation. This prevents accidental platform-specific
  # evaluation (e.g. darwin) caused by some moving inputs. If you later need
  # a fuller registry, we can whitelist safe inputs explicitly.
  # Keep the registry empty to avoid evaluating other inputs during system
  # evaluation. This prevents accidental platform-specific evaluation.
  nix.registry = lib.mkForce { };
  nix = {
    optimise.automatic = true;
    channel.enable = false;
    gc = {
      automatic = true;
      # dates = "weekly"; # default: "03:15"
      options = "--delete-older-than 7d";
    };
    settings = {
      connect-timeout = 5;
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
