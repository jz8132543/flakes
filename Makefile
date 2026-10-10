port ?= 22
device ?= /dev/vda
identity_file ?= /home/tippy/.ssh/id_ed25519
live_ssh_port ?= 2222
live_ssh_window_size ?= 4194304
live_stream_port ?= 2233

update-pkgs:
	./scripts/update-pkgs.sh $(PKGS)

disko:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.disko
diskon:
	nix --experimental-features 'nix-command flakes' build .#nixosConfigurations.${host}.config.system.build.diskoScriptNoDeps
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
upload-key:
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(if $(target_host),$(target_host),$(if $(ip),root@$(ip),))))
	$(eval target_disk ?= $(if $(disk),$(disk),$(device)))
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make upload-key host=<flake-name> ip=<target-ip> [port=22] disk=<device> [identity_file=...]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: target missing. Usage: make upload-key host=<flake-name> ip=<target-ip> [port=22] disk=<device> [identity_file=...]"; exit 1; fi
	@if [ -z "$(target_disk)" ]; then echo "Error: disk missing. Usage: make upload-key host=<flake-name> ip=<target-ip> [port=22] disk=<device> [identity_file=...]"; exit 1; fi
	bash ./scripts/upload-key.sh --host "$(host)" --target-host "$(deploy_target)" --port "$(port)" --device "$(target_disk)" $(if $(identity_file),--identity-file "$(identity_file)",) $(if $(key_src),--key-src "$(key_src)",)

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

deploy-live-kexec-anywhere:
	$(eval port ?= 22)
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	$(eval target_cache ?= off)
	$(eval kexec_local_only ?= on)
	@if [ -z "$(host)" ]; then echo "Error: 'host' not specified. Usage: make deploy-live-kexec-anywhere host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make deploy-live-kexec-anywhere host=<flake-name> target-host=<user@ip> [port=22] [target_cache=on|off] [kexec_url=...] [kexec_attr=...] [kexec_local_only=on|off]"; exit 1; fi
	bash ./scripts/nixos-anywhere-deploy.sh --host "$(host)" --target-host "$(deploy_target)" --port "$(port)" --target-cache "$(target_cache)" --kexec-local-only "$(kexec_local_only)" $(if $(kexec_url),--kexec-url "$(kexec_url)",) $(if $(kexec_attr),--kexec-attr "$(kexec_attr)",)

deploy-reinstall-dd:
	$(eval deploy_target ?= $(if $(target-host),$(target-host),$(target_host)))
	$(eval port ?= 22)
	$(eval dd_only ?= off)
	@if [ -z "$(deploy_target)" ]; then echo "Error: 'target-host' not specified. Usage: make deploy-reinstall-dd host=<flake-name> target-host=<user@ip> device=<device> [port=22] [reinstall_ssh_port=<port>] [identity_file=...] [password=...] [dd_only=on|off]"; exit 1; fi
	@if [ -z "$(device)" ]; then echo "Error: 'device' not specified. Usage: make deploy-reinstall-dd host=<flake-name> target-host=<user@ip> device=<device> [port=22] [reinstall_ssh_port=<port>] [identity_file=...] [password=...] [dd_only=on|off]"; exit 1; fi
	bash ./scripts/deploy-reinstall-dd.sh $(if $(host),--host "$(host)",) --target-host "$(deploy_target)" --device "$(device)" --port "$(port)" $(if $(reinstall_ssh_port),--reinstall-ssh-port "$(reinstall_ssh_port)",) $(if $(identity_file),--identity-file "$(identity_file)",) $(if $(password),--password "$(password)",) $(if $(img_url),--img-url "$(img_url)",) $(if $(filter on ON true TRUE yes YES 1,$(dd_only)),--dd-only,)
