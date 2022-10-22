{ ... }: {

  imports = [
    ./environment
    ./services
    ./sops
    ./openssh
    ./nix
    ./networking
    ./tools
  ];
}

