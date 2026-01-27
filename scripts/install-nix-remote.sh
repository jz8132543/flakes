#!/usr/bin/env bash
set -e

# Default variables
HOST=$1
USER=$2
PORT=${3:-22}
SYSTEM="x86_64-linux"

if [ -z "$HOST" ] || [ -z "$USER" ]; then
  echo "Usage: $0 <host> <user> [port]"
  exit 1
fi

# Check if Nix is already installed on remote
echo "=== Checking for existing Nix installation on $USER@$HOST... ==="
if ssh -p "$PORT" "$USER@$HOST" "test -f ~/.nix-profile/etc/profile.d/nix.sh && test -d /nix/store"; then
  echo "Nix is already installed on $HOST."

  # Check if nix-store is in PATH (required for nix copy)
  echo "Checking if nix-store is in PATH..."
  if ! ssh -p "$PORT" "$USER@$HOST" "which nix-store >/dev/null 2>&1"; then
    echo "nix-store found but NOT in PATH. Attempting to fix shell configuration..."
    ssh -p "$PORT" "$USER@$HOST" '
            NIX_PROFILE="$HOME/.nix-profile/etc/profile.d/nix.sh"
            if [ -f "$NIX_PROFILE" ]; then
                # Add to .zshenv for non-interactive Zsh
                if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
                    if ! grep -q "source $NIX_PROFILE" ~/.zshenv 2>/dev/null; then
                        echo "Adding source $NIX_PROFILE to ~/.zshenv"
                        echo "if [ -f $NIX_PROFILE ]; then source $NIX_PROFILE; fi" >> ~/.zshenv
                    fi
                fi
                # Add to .bashrc for Bash
                if ! grep -q "source $NIX_PROFILE" ~/.bashrc 2>/dev/null; then
                    echo "Adding source $NIX_PROFILE to ~/.bashrc"
                    echo "if [ -f $NIX_PROFILE ]; then source $NIX_PROFILE; fi" >> ~/.bashrc
                fi
            fi
        '
    echo "Shell configuration updated."
  else
    echo "nix-store is in PATH. Good."
  fi

  echo "Skipping installation."
  exit 0
fi

echo "=== Detecting latest Nix version ==="
# Try 1: GitHub API (requires internet)
LATEST_VERSION=$(curl -s https://api.github.com/repos/NixOS/nix/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
# Try 2: Local Nix version (fallback)
if [ -z "$LATEST_VERSION" ]; then
  echo "Warning: Could not fetch latest version from GitHub. Trying local Nix version..."
  LATEST_VERSION=$(nix --version 2>/dev/null | awk '{print $3}')
fi
# Try 3: Hardcoded fallback
NIX_VERSION="${LATEST_VERSION:-2.18.1}"
echo "Using Nix version: $NIX_VERSION"

TARBALL_NAME="nix-${NIX_VERSION}-${SYSTEM}.tar.xz"
LOCAL_TARBALL="/tmp/$TARBALL_NAME"
DOWNLOAD_URL="https://nixos.org/releases/nix/nix-${NIX_VERSION}/${TARBALL_NAME}"

echo "=== Ensuring Nix binary tarball exists locally ==="
if [ ! -f "$LOCAL_TARBALL" ]; then
  echo "Downloading $TARBALL_NAME to /tmp..."
  curl -L -o "$LOCAL_TARBALL" "$DOWNLOAD_URL"
else
  echo "Found local $LOCAL_TARBALL, skipping download."
fi

echo "=== Copying Nix installer to remote host ($USER@$HOST:$PORT) ==="
scp -P "$PORT" "$LOCAL_TARBALL" "$USER@$HOST:~/$TARBALL_NAME"

echo "=== Installing Nix on remote host ==="
REMOTE_SCRIPT="scripts/remote-install.sh"

# Copy the remote script
scp -P "$PORT" "$REMOTE_SCRIPT" "$USER@$HOST:~/remote-install.sh"

# Execute the remote script with arguments
ssh -p "$PORT" "$USER@$HOST" "bash ~/remote-install.sh '$TARBALL_NAME' '$NIX_VERSION' '$SYSTEM' && rm ~/remote-install.sh"

echo "=== Nix installation complete! ==="
echo "You may need to log out and log back in on the remote host, or source the profile."
