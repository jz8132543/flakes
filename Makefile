disko:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.disko
diskon:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.diskoNoDeps
build:
	nix --experimental-features 'nix-command flakes' build --builders "ssh://${builder}" .#nixosConfigurations.${host}.config.system.build.toplevel

nixos-anywhere:
	$(eval port ?= 22)
	$(eval flake_host ?= $(if $(host),$(host),$(hostname)))
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	$(eval target_cache ?= off)
	$(eval kexec_local_only ?= on)
	@if [ -z "$(flake_host)" ]; then echo "Error: 'host' not specified. Usage: make nixos-anywhere host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make nixos-anywhere host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	# host = flake machine name, target-host = remote SSH address/IP
	bash ./scripts/nixos-anywhere-deploy.sh --host "$(flake_host)" --target-host "$(deploy_target)" --port "$(port)" --target-cache "$(target_cache)" --kexec-local-only "$(kexec_local_only)" $(if $(kexec_url),--kexec-url "$(kexec_url)",) $(if $(kexec_attr),--kexec-attr "$(kexec_attr)",)
mount:
	nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- --mode mount -f .#${host}
rebuild-boot:
	nixos-enter --root /mnt -- nixos-rebuild boot --flake 'https://github.com/jz8132543/flakes'#${host} --install-bootloader

generate-hardware:
	nix run github:nix-community/nixos-anywhere -- \
		--flake .#${host} \
		--generate-hardware-config nixos-generate-config ./nixos/hosts/${host}/hardware.nix \
		root@${IP}


deploy-home: install-nix
	$(eval user ?= tippy)
	$(eval port ?= 22)
	$(eval build_host ?= $(host))
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make deploy-home host=<host> [user=...]"; exit 1; fi
	ssh-keygen -R [${host}]:${port} || true
	./scripts/deploy.sh ${host} ${user} ${port} ${build_host}

install-nix:
	$(eval user ?= tippy)
	$(eval port ?= 22)
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make install-nix host=<host>"; exit 1; fi
	./scripts/install-nix-remote.sh ${host} ${user} ${port}

# img-deploy-image:
# 	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.sdImage -o result

# img-deploy:
# 	$(eval user ?= root)
# 	$(eval port ?= 22)
# 	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make img-deploy host=<host> user=<user> device=<device> [port=22]"; exit 1; fi
# 	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make img-deploy host=<host> user=<user> device=<device> [port=22]"; exit 1; fi
# 	./scripts/img-deploy.sh --target .#nixosConfigurations.${host}.config.system.build.sdImage --host ${host} --user ${user} --port ${port} --device ${device}

# deploy-raw:
# 	$(eval user ?= root)
# 	$(eval port ?= 22)
# 	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make deploy-raw host=<host> user=<user> device=<device> [port=22]"; exit 1; fi
# 	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make deploy-raw host=<host> user=<user> device=<device> [port=22]"; exit 1; fi
# 	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.diskoImages --host ${host} --user ${user} --port ${port} --device ${device}

# Phase 1: Only build the image
build-raw:
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make build-raw host=<host>"; exit 1; fi
	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.diskoImages --only-build

build-repart:
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make build-repart host=<host>"; exit 1; fi
	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.image --only-build

# Phase 2: Only stream the image
stream-raw:
	$(eval port ?= 22)
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make stream-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make stream-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make stream-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.diskoImages --target-host "${deploy_target}" --port "${port}" --device "${device}" --only-stream

stream-repart:
	$(eval port ?= 22)
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make stream-repart host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make stream-repart host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make stream-repart host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.image --target-host "${deploy_target}" --port "${port}" --device "${device}" --only-stream

# Special: Install onto a running Linux host via kexec into an in-memory installer.
# This keeps SSH available on the installer side, so transient client disconnects
# do not abort the whole deployment like raw disk streaming does.
deploy-live:
	$(eval port ?= 22)
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	$(eval target_cache ?= off)
	$(eval kexec_local_only ?= on)
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make deploy-live host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make deploy-live host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	bash ./scripts/nixos-anywhere-deploy.sh --host "$(host)" --target-host "$(deploy_target)" --port "$(port)" --target-cache "$(target_cache)" --kexec-local-only "$(kexec_local_only)" $(if $(kexec_url),--kexec-url "$(kexec_url)",) $(if $(kexec_attr),--kexec-attr "$(kexec_attr)",)

# Legacy raw live overwrite mode. This writes the image directly over the
# running system via a single SSH pipeline and cannot safely survive disconnects.
deploy-live-raw:
	$(eval port ?= 22)
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make deploy-live-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make deploy-live-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make deploy-live-raw host=<flake-name> target-host=<user@ip> device=<device> [port=22]"; exit 1; fi
	./scripts/deploy-raw-image.sh --target .#nixosConfigurations.${host}.config.system.build.diskoImages --target-host "${deploy_target}" --port "${port}" --device "${device}" --live-overwrite
