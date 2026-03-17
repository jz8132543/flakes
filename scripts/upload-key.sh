#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: upload-key.sh --host NAME --target-host root@IP --device /dev/vdX [options]

Options:
  --host NAME           Flake host name, e.g. surface
  --target-host USER@IP Remote SSH target, e.g. root@1.2.3.4
  --port PORT           SSH port (default: 22)
  --device PATH         Target block device, e.g. /dev/vda
  --identity-file PATH  SSH private key
  --key-src PATH        Local sops-nix key path (default: /var/lib/sops-nix/key)
  --help                Show this help
EOF
}

log() {
  printf '[upload-key] %s\n' "$*"
}

die() {
  printf '[upload-key] %s\n' "$*" >&2
  exit 1
}

quote_for_sh() {
  printf '%q' "$1"
}

HOST=""
TARGET_HOST=""
PORT=22
DEVICE=""
IDENTITY_FILE=""
KEY_SRC="/var/lib/sops-nix/key"
TEMP_DIR=""
TARGET_SYSTEM=""

SSH_BASE_OPTS=()
SSH_AUTH_OPTS=()
SCP_BASE_OPTS=()

REMOTE_BASE=""
REMOTE_ROOT=""
REMOTE_BIN=""
REMOTE_BUSYBOX=""
REMOTE_BASH=""
REMOTE_FINDMNT=""
REMOTE_MOUNT=""
REMOTE_DISKO_MOUNT=""
REMOTE_KEY=""

LOCAL_BUSYBOX=""
LOCAL_BASH=""
LOCAL_FINDMNT=""
LOCAL_MOUNT=""
LOCAL_DISKO_MOUNT=""

cleanup() {
  if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}"
  fi
}

trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --target-host | --target)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --device | --disk)
      DEVICE="${2:-}"
      shift 2
      ;;
    --identity-file)
      IDENTITY_FILE="${2:-}"
      shift 2
      ;;
    --key-src)
      KEY_SRC="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  [ -n "${HOST}" ] || die "Missing --host"
  [ -n "${TARGET_HOST}" ] || die "Missing --target-host"
  [ -n "${DEVICE}" ] || die "Missing --device"
  [ -f "${KEY_SRC}" ] || die "Missing key file: ${KEY_SRC}"
}

prepare_temp_dir() {
  if [ -z "${TEMP_DIR}" ]; then
    TEMP_DIR="$(mktemp -d)"
  fi
}

resolve_identity_file() {
  local candidate

  if [ -n "${IDENTITY_FILE}" ]; then
    [ -f "${IDENTITY_FILE}" ] || die "Identity file not found: ${IDENTITY_FILE}"
    return
  fi

  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    if [ -f "${candidate}" ]; then
      IDENTITY_FILE="${candidate}"
      return
    fi
  done < <(ssh -G -p "${PORT}" "${TARGET_HOST}" 2>/dev/null | awk '/^identityfile / { print $2 }')

  if [ -f "${HOME}/.ssh/id_ed25519" ]; then
    IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
  fi
}

setup_ssh() {
  SSH_BASE_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=4
    -o ControlMaster=no
    -p "${PORT}"
  )

  SSH_AUTH_OPTS=()
  if [ -n "${IDENTITY_FILE}" ]; then
    SSH_AUTH_OPTS=(-i "${IDENTITY_FILE}")
  fi

  SCP_BASE_OPTS=(
    -C
    -o StrictHostKeyChecking=accept-new
    -P "${PORT}"
  )

  if [ -n "${IDENTITY_FILE}" ]; then
    SCP_BASE_OPTS+=(-i "${IDENTITY_FILE}")
  fi
}

remote_ssh() {
  ssh "${SSH_BASE_OPTS[@]}" "${SSH_AUTH_OPTS[@]}" "${TARGET_HOST}" "$@"
}

upload_file() {
  local local_path="$1"
  local remote_path="$2"
  local mode="${3:-0644}"
  local remote_dir=""

  remote_dir="$(dirname "${remote_path}")"
  remote_ssh "mkdir -p $(quote_for_sh "${remote_dir}")"
  cat "${local_path}" | remote_ssh "cat > $(quote_for_sh "${remote_path}") && chmod ${mode} $(quote_for_sh "${remote_path}")"
}

discover_remote_base() {
  REMOTE_BASE="$(
    remote_ssh '
      set -eu

      pick_exec_dir() {
        local base="$1"
        local probe_dir=""
        local probe_file=""

        [ -d "$base" ] || return 1
        [ -w "$base" ] || return 1

        probe_dir="$base/.upload-key-probe-$$"
        probe_file="$probe_dir/probe.sh"

        rm -rf "$probe_dir"
        mkdir -p "$probe_dir" || return 1
        printf "%s\n" "#!/bin/sh" "exit 0" >"$probe_file" || return 1
        chmod 700 "$probe_file" || return 1

        if "$probe_file" >/dev/null 2>&1; then
          rm -rf "$probe_dir"
          printf "%s" "$base"
          return 0
        fi

        rm -rf "$probe_dir"
        return 1
      }

      for base in /run /tmp /var/tmp /root /dev/shm; do
        if pick_exec_dir "$base"; then
          exit 0
        fi
      done

      exit 1
    '
  )" || die "Could not find a writable executable remote temp directory"

  REMOTE_ROOT="${REMOTE_BASE}/upload-key-$$"
  REMOTE_BIN="${REMOTE_ROOT}/bin"
  REMOTE_BUSYBOX="${REMOTE_BIN}/busybox"
  REMOTE_BASH="${REMOTE_BIN}/bash"
  REMOTE_FINDMNT="${REMOTE_BIN}/findmnt"
  REMOTE_MOUNT="${REMOTE_BIN}/mount"
  REMOTE_DISKO_MOUNT="${REMOTE_ROOT}/disko-mount.sh"
  REMOTE_KEY="${REMOTE_ROOT}/key"
}

build_out_path() {
  local attr="$1"
  nix build \
    --no-link \
    --print-out-paths \
    --experimental-features 'nix-command flakes' \
    "$attr"
}

build_bin_from_attr() {
  local attr="$1"
  local rel_bin="$2"
  local out=""

  while IFS= read -r out; do
    if [ -x "${out}/${rel_bin}" ]; then
      printf '%s\n' "${out}/${rel_bin}"
      return 0
    fi
  done < <(build_out_path "${attr}")

  return 1
}

prepare_local_artifacts() {
  log "Resolving target system for ${HOST}"
  TARGET_SYSTEM="$(nix eval --raw --experimental-features 'nix-command flakes' ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")"

  log "Building tiny remote runtime for ${TARGET_SYSTEM}"
  LOCAL_BUSYBOX="$(build_bin_from_attr "nixpkgs#legacyPackages.${TARGET_SYSTEM}.pkgsStatic.busybox" "bin/busybox")"
  LOCAL_BASH="$(build_bin_from_attr "nixpkgs#legacyPackages.${TARGET_SYSTEM}.pkgsStatic.bash" "bin/bash")"
  LOCAL_FINDMNT="$(build_bin_from_attr "nixpkgs#legacyPackages.${TARGET_SYSTEM}.pkgsStatic.util-linux" "bin/findmnt")"
  LOCAL_MOUNT="$(build_bin_from_attr "nixpkgs#legacyPackages.${TARGET_SYSTEM}.pkgsStatic.util-linux" "bin/mount")"
  LOCAL_DISKO_MOUNT="$(build_out_path ".#nixosConfigurations.${HOST}.config.system.build.mountScriptNoDeps")"

  [ -x "${LOCAL_BUSYBOX}" ] || die "Missing busybox binary"
  [ -x "${LOCAL_BASH}" ] || die "Missing bash binary"
  [ -x "${LOCAL_FINDMNT}" ] || die "Missing findmnt binary"
  [ -x "${LOCAL_MOUNT}" ] || die "Missing mount binary"
  [ -e "${LOCAL_DISKO_MOUNT}" ] || die "Missing disko mount script"
}

show_local_sizes() {
  log "Upload set:"
  ls -lh \
    "${LOCAL_BUSYBOX}" \
    "${LOCAL_BASH}" \
    "${LOCAL_FINDMNT}" \
    "${LOCAL_MOUNT}" \
    "${LOCAL_DISKO_MOUNT}" | sed 's/^/[upload-key]   /'
}

prepare_remote_runtime() {
  log "Uploading minimal runtime to ${TARGET_HOST}"
  remote_ssh "rm -rf $(quote_for_sh "${REMOTE_ROOT}") && mkdir -p $(quote_for_sh "${REMOTE_BIN}")"

  upload_file "${LOCAL_BUSYBOX}" "${REMOTE_BUSYBOX}" 0755
  upload_file "${LOCAL_BASH}" "${REMOTE_BASH}" 0755
  upload_file "${LOCAL_FINDMNT}" "${REMOTE_FINDMNT}" 0755
  upload_file "${LOCAL_MOUNT}" "${REMOTE_MOUNT}" 0755
  upload_file "${LOCAL_DISKO_MOUNT}" "${REMOTE_DISKO_MOUNT}" 0755
  upload_file "${KEY_SRC}" "${REMOTE_KEY}" 0600
}

run_remote_install() {
  local remote_dest="/mnt/persist/var/lib/sops-nix/key"
  local remote_dir="/mnt/persist/var/lib/sops-nix"
  local remote_path="${REMOTE_BIN}:/usr/sbin:/usr/bin:/sbin:/bin"
  local efi_part=""
  local nixos_part=""

  case "${DEVICE}" in
  *[0-9])
    efi_part="${DEVICE}p2"
    nixos_part="${DEVICE}p3"
    ;;
  *)
    efi_part="${DEVICE}2"
    nixos_part="${DEVICE}3"
    ;;
  esac

  log "Running remote mount + key install on ${TARGET_HOST}"
  remote_ssh "
    set -eu
    export PATH=$(quote_for_sh "${remote_path}"):\$PATH

    if ! test -b $(quote_for_sh "${DEVICE}"); then
      echo \"target block device missing: ${DEVICE}\" >&2
      exit 1
    fi
    if ! test -b $(quote_for_sh "${efi_part}"); then
      echo \"expected EFI partition missing: ${efi_part}\" >&2
      cat /proc/partitions >&2 || true
      exit 1
    fi
    if ! test -b $(quote_for_sh "${nixos_part}"); then
      echo \"expected NIXOS partition missing: ${nixos_part}\" >&2
      cat /proc/partitions >&2 || true
      exit 1
    fi
    test -d /dev/disk/by-partlabel || mkdir /dev/disk/by-partlabel
    ln -sfn $(quote_for_sh "${efi_part}") /dev/disk/by-partlabel/EFI
    ln -sfn $(quote_for_sh "${nixos_part}") /dev/disk/by-partlabel/NIXOS

    $(quote_for_sh "${REMOTE_BASH}") $(quote_for_sh "${REMOTE_DISKO_MOUNT}")

    test -d /mnt/persist/var || mkdir /mnt/persist/var
    test -d /mnt/persist/var/lib || mkdir /mnt/persist/var/lib
    test -d $(quote_for_sh "${remote_dir}") || mkdir $(quote_for_sh "${remote_dir}")
    install -m 0644 $(quote_for_sh "${REMOTE_KEY}") $(quote_for_sh "${remote_dest}")
    chmod a+r $(quote_for_sh "${remote_dest}")
    sync
    rm -rf $(quote_for_sh "${REMOTE_ROOT}")
  "
}

main() {
  parse_args "$@"
  prepare_temp_dir
  resolve_identity_file
  setup_ssh
  discover_remote_base
  prepare_local_artifacts

  show_local_sizes
  prepare_remote_runtime
  run_remote_install

  log "Done"
  log "Target: ${TARGET_HOST}  port=${PORT}  disk=${DEVICE}"
}

main "$@"
