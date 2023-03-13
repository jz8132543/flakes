#!/usr/bin/env bash

# MIT Licensed - 2021 Zhaofeng Li

set -euo pipefail

log() {
	>&2 echo -ne "\033[1m\033[34m*** "
	>&2 echo -n "$@"
	>&2 echo -e "\033[0m"
}

error() {
	>&2 echo -ne "\033[1m\033[31m*** Error: "
	>&2 echo -n "$@"
	>&2 echo -e "\033[0m"
}

nix() {
	(run env nix --experimental-features nix-command "$@")
}

run() {
	set -x
	exec -- "$@"
}

ssh() {
	(run env ssh $NIX_SSHOPTS $@)
}

finish() {
	ret=$?

	set +eu

	log "Cleaning up..."

	if [[ -n "${target}" && -n "${tmpdir}" ]]; then
		log "Disconnecting from host..."
		run ssh -o "ControlPath ${tmpdir}/ssh.sock" -O exit "${target}"
	fi

	rm -rf "${tmpdir}"

	if [[ "${ret}" != "0" ]]; then
		log "Return Code -> ${ret}"
	fi

	exit $ret
}

trap finish EXIT

if [[ "$#" != "2" ]]; then
	>&2 echo "Usage: $0 [name of host] [mountpoint]"
	>&2 echo "Example: $0 somehost /mnt"
	exit 1
fi

name=$1
mountpoint=$2

if [[ "${mountpoint}" = "" ]]; then
	error "Mountpoint cannot be empty!"
	exit 1
fi

tmpdir=$(mktemp -d)
log "Our temporary directory is ${tmpdir}"

# The argument expansion for NIX_SSHOPTS is broken and we can't
# directly put "quoted arguments with spaces" :(
echo -e "ControlMaster auto\nControlPath ${tmpdir}/ssh.sock\nControlPersist 30m" > $tmpdir/ssh_config
export NIX_SSHOPTS="-F ${tmpdir}/ssh_config"

log "Getting SSH target..."
target=$(run colmena eval -E "{ nodes, ... }: with nodes.\"$name\".config.deployment; \"\${targetUser}@\${targetHost}\"" | jq -r)

log "~~~~~~"
log "Deploying to ${target} on mountpoint ${mountpoint}"
log "~~~~~~"

log "Obtaining a persistent connection..."
ssh "${target}" true
log "-> Success"

log "Evaluating configuration... "
drv=$(run colmena eval --instantiate -E "{ nodes, ... }: nodes.\"$name\".config.system.build.toplevel")
log "-> ${drv}"

log "Building configuration..."
system=$(run nix-build $drv)
log "-> ${system}"

log "Pushing configuration..."
nix copy -s --to "ssh://${target}?remote-store=local?root=${mountpoint}" "${system}"
log "-> Pushed"

log "Activating configuration..."
if [[ "${mountpoint}" == "/" ]]; then
	ssh "${target}" -- "nix-env --profile /nix/var/nix/profiles/system --set ${system} && NIXOS_INSTALL_BOOTLOADER=1 ${system}/bin/switch-to-configuration boot"
else
	ssh "${target}" -- "mkdir -p ${mountpoint}/etc && touch ${mountpoint}/etc/NIXOS && nix-env --store ${mountpoint} --profile ${mountpoint}/nix/var/nix/profiles/system --set ${system} && NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root ${mountpoint} -- /run/current-system/bin/switch-to-configuration boot"
fi

log "All done!"
