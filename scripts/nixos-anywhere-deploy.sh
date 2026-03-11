#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixos-anywhere-deploy.sh --host NAME --target-host user@host [options]

Options:
  --port PORT                    SSH port for the target host (default: 22)
  --target-cache on|off          Whether the target installer may use binary caches (default: off)
  --kexec-url URL_OR_PATH        Kexec tarball URL or local file path
  --kexec-local-only on|off      Require kexec tarball to exist on the build host first (default: on)

Behavior:
1. Build nixos-anywhere, the target toplevel, and the disko script on the build host.
2. Download the kexec tarball on the build host and force upload it to the target via --kexec when --kexec-local-only=on.
3. Optionally inject a temporary installer nix.conf so the target can use binary caches.
EOF
  exit 1
}

log() {
  printf '[nixos-anywhere-deploy] %s\n' "$*"
}

die() {
  printf '[nixos-anywhere-deploy] %s\n' "$*" >&2
  exit 1
}

HOST=""
TARGET_HOST=""
PORT=22
TARGET_CACHE="off"
KEXEC_URL=""
KEXEC_LOCAL_ONLY="on"

BUILD_SYSTEM=""
HOST_SYSTEM=""
NIXOS_ANYWHERE_BIN=""
TOPLEVEL_PATH=""
DISKO_SCRIPT_PATH=""
KEXEC_TARBALL_PATH=""
TEMP_DIR=""
INSTALLER_NIX_CONF_PATH=""

cleanup() {
  if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}"
  fi
}

trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --host | --hostname)
      HOST="$2"
      shift 2
      ;;
    --target-host | --target)
      TARGET_HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --target-cache)
      TARGET_CACHE="$2"
      shift 2
      ;;
    --target-cache=*)
      TARGET_CACHE="${1#*=}"
      shift 1
      ;;
    --kexec-url)
      KEXEC_URL="$2"
      shift 2
      ;;
    --kexec-url=*)
      KEXEC_URL="${1#*=}"
      shift 1
      ;;
    --kexec-local-only)
      KEXEC_LOCAL_ONLY="$2"
      shift 2
      ;;
    --kexec-local-only=*)
      KEXEC_LOCAL_ONLY="${1#*=}"
      shift 1
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  if [ -z "$HOST" ] || [ -z "$TARGET_HOST" ]; then
    usage
  fi

  case "${TARGET_CACHE}" in
  on | off) ;;
  *)
    die "Unsupported --target-cache value: ${TARGET_CACHE} (expected: on|off)"
    ;;
  esac

  case "${KEXEC_LOCAL_ONLY}" in
  on | off) ;;
  *)
    die "Unsupported --kexec-local-only value: ${KEXEC_LOCAL_ONLY} (expected: on|off)"
    ;;
  esac
}

build_attr_path() {
  local attr="$1"
  nix build \
    --no-link \
    --print-out-paths \
    --experimental-features 'nix-command flakes' \
    "$attr"
}

build_out_path() {
  local attr="$1"
  nix build \
    --no-link \
    --print-out-paths \
    --experimental-features 'nix-command flakes' \
    "$attr"
}

eval_attr_raw() {
  nix eval \
    --raw \
    --experimental-features 'nix-command flakes' \
    "$@"
}

dedupe_words() {
  awk '
    {
      for (i = 1; i <= NF; i++) {
        if (!seen[$i]++) {
          out[++n] = $i
        }
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        printf "%s%s", out[i], (i < n ? OFS : ORS)
      }
    }
  ' <<<"$*"
}

prepare_local_nixos_anywhere() {
  local package_attr
  local package_path

  BUILD_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
  package_attr=".#packages.${BUILD_SYSTEM}.nixos-anywhere"

  log "Building local nixos-anywhere package (${package_attr})"
  package_path="$(build_attr_path "$package_attr")"
  NIXOS_ANYWHERE_BIN="${package_path}/bin/nixos-anywhere"

  if [ ! -x "$NIXOS_ANYWHERE_BIN" ]; then
    die "Expected nixos-anywhere binary at ${NIXOS_ANYWHERE_BIN}"
  fi
}

prepare_target_artifacts() {
  log "Building target toplevel for ${HOST}"
  TOPLEVEL_PATH="$(build_attr_path ".#nixosConfigurations.${HOST}.config.system.build.toplevel")"

  log "Building disko script for ${HOST}"
  DISKO_SCRIPT_PATH="$(build_attr_path ".#nixosConfigurations.${HOST}.config.system.build.diskoScriptNoDeps")"

  HOST_SYSTEM="$(eval_attr_raw ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")"

  if [ ! -e "$TOPLEVEL_PATH" ]; then
    die "Missing toplevel store path: ${TOPLEVEL_PATH}"
  fi

  if [ ! -e "$DISKO_SCRIPT_PATH" ]; then
    die "Missing disko script store path: ${DISKO_SCRIPT_PATH}"
  fi
}

default_kexec_package_attr() {
  case "$1" in
  x86_64-linux)
    printf '%s\n' "github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-unstable-noninteractive"
    ;;
  aarch64-linux)
    printf '%s\n' "github:nix-community/nixos-images#packages.aarch64-linux.kexec-installer-nixos-unstable-noninteractive"
    ;;
  *)
    die "Unsupported target system for default kexec package: $1"
    ;;
  esac
}

prepare_temp_dir() {
  if [ -z "${TEMP_DIR}" ]; then
    TEMP_DIR="$(mktemp -d)"
  fi
}

prepare_kexec_tarball() {
  local source
  local package_attr
  local package_path
  local filename

  prepare_temp_dir

  source="${KEXEC_URL}"
  if [ -z "${source}" ]; then
    package_attr="$(default_kexec_package_attr "${HOST_SYSTEM}")"
    log "Building default kexec tarball on build host from ${package_attr}"
    package_path="$(build_out_path "${package_attr}")"
    KEXEC_TARBALL_PATH="${package_path}/nixos-kexec-installer-noninteractive-${HOST_SYSTEM}.tar.gz"
    if [ ! -f "${KEXEC_TARBALL_PATH}" ]; then
      die "Expected kexec tarball at ${KEXEC_TARBALL_PATH}"
    fi
    log "Using built kexec tarball ${KEXEC_TARBALL_PATH}"
    return
  fi

  if [ -f "${source}" ]; then
    KEXEC_TARBALL_PATH="$(readlink -f -- "${source}")"
    log "Using local kexec tarball ${KEXEC_TARBALL_PATH}"
    return
  fi

  if [ "${KEXEC_LOCAL_ONLY}" != "on" ]; then
    KEXEC_TARBALL_PATH="${source}"
    log "Using remote kexec URL ${KEXEC_TARBALL_PATH}"
    return
  fi

  filename="$(basename -- "${source%%\?*}")"
  if [ -z "${filename}" ]; then
    filename="nixos-kexec-installer.tar.gz"
  fi

  KEXEC_TARBALL_PATH="${TEMP_DIR}/${filename}"
  log "Downloading kexec tarball on build host from ${source}"
  if ! curl --fail --location --silent --show-error --output "${KEXEC_TARBALL_PATH}" "${source}"; then
    die "Failed to fetch kexec tarball on build host: ${source}"
  fi
}

prepare_target_cache_config() {
  local substituters
  local trusted_public_keys

  if [ "${TARGET_CACHE}" != "on" ]; then
    return
  fi

  prepare_temp_dir
  INSTALLER_NIX_CONF_PATH="${TEMP_DIR}/installer-nix.conf"
  substituters="$(eval_attr_raw --apply toString ".#nixosConfigurations.${HOST}.config.nix.settings.substituters")"
  trusted_public_keys="$(eval_attr_raw --apply toString ".#nixosConfigurations.${HOST}.config.nix.settings.trusted-public-keys")"

  case " ${substituters} " in
  *" https://mirrors.ustc.edu.cn/nix-channels/store "*) ;;
  *)
    substituters="${substituters} https://mirrors.ustc.edu.cn/nix-channels/store"
    ;;
  esac

  substituters="$(dedupe_words "${substituters}")"
  trusted_public_keys="$(dedupe_words "${trusted_public_keys}")"

  {
    printf 'extra-substituters = %s\n' "${substituters}"
    printf 'extra-trusted-public-keys = %s\n' "${trusted_public_keys}"
    printf 'connect-timeout = 1\n'
    printf 'stalled-download-timeout = 1\n'
    printf 'fallback = true\n'
  } >"${INSTALLER_NIX_CONF_PATH}"

  log "Prepared temporary installer nix.conf with target-side cache settings"
}

run_nixos_anywhere() {
  local cmd=(
    "$NIXOS_ANYWHERE_BIN"
    "--kexec"
    "$KEXEC_TARBALL_PATH"
    "--store-paths"
    "$DISKO_SCRIPT_PATH"
    "$TOPLEVEL_PATH"
    "$TARGET_HOST"
    "-p"
    "$PORT"
  )

  if [ "${TARGET_CACHE}" = "on" ]; then
    cmd+=(
      "--disk-encryption-keys"
      "/root/.config/nix/nix.conf"
      "$INSTALLER_NIX_CONF_PATH"
      "--no-use-machine-substituters"
    )
  else
    cmd+=("--no-substitute-on-destination")
  fi

  log "Running nixos-anywhere"
  "${cmd[@]}"
}

main() {
  parse_args "$@"
  prepare_local_nixos_anywhere
  prepare_target_artifacts
  prepare_kexec_tarball
  prepare_target_cache_config
  run_nixos_anywhere
  log "Done."
}

main "$@"
