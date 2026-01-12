disko:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.disko
diskon:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.diskoNoDeps
build:
  nix --experimental-features 'nix-command flakes' build --builders "ssh://${builder}" .#nixosConfigurations.${host}.config.system.build.toplevel
nixos-anywhere:
  nix run github:nix-community/nixos-anywhere -- --flake .#${host} root@${host} --no-substitute-on-destination
mount:
  nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- --mode mount -f .#${host}
rebuild-boot:
  nixos-enter --root /mnt -- nixos-rebuild boot --flake 'https://github.com/jz8132543/flakes'#${host} --install-bootloader
