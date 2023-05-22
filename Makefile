disko:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.disko
diskon:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.diskoNoDeps
build:
  nix --experimental-features 'nix-command flakes' build --builders "ssh://${builder}" .#nixosConfigurations.${host}.config.system.build.toplevel
