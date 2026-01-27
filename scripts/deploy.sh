#!/usr/bin/env bash
set -e

# Usage: ./scripts/deploy.sh <HOST> <USER> <PORT> <BUILD_HOST>
HOST=$1
USER=${2:-tippy}
PORT=${3:-22}
BUILD_HOST=${4:-localhost}

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
nix copy --to "ssh://${USER}@${HOST}:${PORT}" "$ACTIVATION_PKG"

echo "=== 3. Activating Configuration ==="
# We assume the remote host might have conflicting files (like .zshrc created by installer),
# so we enable automatic backup by setting HOME_MANAGER_BACKUP_EXT.
# This is the standard mechanism provided by Home Manager's activation script.
CMD="source ~/.nix-profile/etc/profile.d/nix.sh; export HOME_MANAGER_BACKUP_EXT=backup; $ACTIVATION_PKG/activate"

ssh -p "$PORT" "$USER@$HOST" "$CMD"

echo "=== Deployment Complete! ==="
