#!/usr/bin/env bash
set -e

# Usage: ./scripts/deploy.sh <HOST> <USER> <PORT> <BUILD_HOST>
HOST=$1
USER=${2:-tippy}
PORT=${3:-22}
BUILD_HOST=${4:-$HOST}

if [ -z "$HOST" ]; then
  echo "Usage: $0 <HOST> [USER] [PORT] [BUILD_HOST]"
  exit 1
fi

FLAKE_ATTR="homeConfigurations.\"${USER}@${BUILD_HOST}\".activationPackage"

echo "=== 1. Building Configuration ($FLAKE_ATTR) ==="
# We use --no-link to avoid creating ./result symlink clutter
# and --print-out-paths to get the path directly
ACTIVATION_PKG=$(nix build ".#$FLAKE_ATTR" --impure --print-out-paths --no-link)

if [ -z "$ACTIVATION_PKG" ]; then
  echo "Error: Build failed or produced no output."
  exit 1
fi

echo "Build successful: $ACTIVATION_PKG"

echo "=== 2. Copying to Remote ($USER@$HOST:$PORT) ==="
# --no-check-sigs allows copying paths that aren't signed by a trusted key (required for non-trusted-users)
# We specify remote-program to ensure nix-daemon can be found even if not in PATH
nix copy --no-check-sigs --to "ssh-ng://${USER}@${HOST}:${PORT}?remote-program=~/.nix-profile/bin/nix-daemon" "$ACTIVATION_PKG"

echo "=== 3. Activating Configuration ==="
# We use bash -c to ensure the command runs in a POSIX-compatible shell even if the remote user's shell is fish.
CMD="bash -c 'source ~/.profile 2>/dev/null || true; [ -f ~/.nix-profile/etc/profile.d/nix.sh ] && source ~/.nix-profile/etc/profile.d/nix.sh; export HOME_MANAGER_BACKUP_EXT=backup; $ACTIVATION_PKG/activate'"

ssh -p "$PORT" "$USER@$HOST" "$CMD"

echo "=== Deployment Complete! ==="
