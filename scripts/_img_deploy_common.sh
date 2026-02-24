#!/usr/bin/env sh
set -eu

log() { printf '%s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

confirm() {
  if [ "${FORCE:-}" = "yes" ]; then return 0; fi
  printf "%s [y/N]: " "$1"
  read -r ans
  case "$ans" in
  y | Y | yes | YES) return 0 ;;
  *) return 1 ;;
  esac
}

ensure_ssh_key() {
  user_at_host="$1"
  port="$2"
  no_key_install="${3:-no}"
  if [ "$no_key_install" = "yes" ]; then
    log "Skipping ssh-key install as requested"
    return 0
  fi
  if ssh -p "$port" -o BatchMode=yes "$user_at_host" true 2>/dev/null; then
    log "Passwordless SSH already works for $user_at_host"
    return 0
  fi
  log "Attempting to install SSH key to $user_at_host (will prompt for password)"
  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -p "$port" "$user_at_host" || die "ssh-copy-id failed"
  else
    die "ssh-copy-id not available; please install or add key manually"
  fi
}

get_nix_image_path() {
  target="$1"
  log "Building nix target ${target} ..."
  nix --experimental-features 'nix-command flakes' build "$target"
  path=$(readlink -f result || true)
  if [ -z "$path" ]; then
    die "nix build did not produce a result symlink"
  fi
  img=$(find "$path" -maxdepth 2 -type f \( -name '*.img' -o -name '*sd*.img' -o -name '*.raw' \) | head -n1 || true)
  if [ -z "$img" ]; then
    if [ -f "$path" ]; then
      img="$path"
    else
      die "Cannot find image file in $path; inspect build outputs"
    fi
  fi
  printf '%s' "$img"
}
