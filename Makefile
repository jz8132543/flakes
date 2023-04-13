secret:
	./scripts/update_sops_secrets

disko:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.disko
diskon:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.diskoNoDeps
