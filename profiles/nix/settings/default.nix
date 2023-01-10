{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      system-features = [ ];

      auto-optimise-store = true;
      # automatic = true;

      sandbox = true;

      allowed-users = [ "@users" ];
      trusted-users = [ "root" "@wheel" ];

      keep-outputs = true;
      keep-derivations = true;
      fallback = true;
    };
    extraOptions = ''
      experimental-features = nix-command flakes
      system-features = kvm big-parallel
      # warn-dirty = false
    '';
    package = pkgs.nixFlakes; # or versioned attributes like nixVersions.nix_2_8
  };
}
