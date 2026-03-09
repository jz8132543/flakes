#!/usr/bin/env bash
set -euo pipefail

# These variables will be passed as arguments
TARBALL_NAME=$1
NIX_VERSION=$2
SYSTEM=$3

if [ -z "$TARBALL_NAME" ] || [ -z "$NIX_VERSION" ] || [ -z "$SYSTEM" ]; then
  echo "Usage: remote-install.sh <TARBALL_NAME> <NIX_VERSION> <SYSTEM>"
  exit 1
fi

mkdir -p ~/nix-install
tar -xf ~/"$TARBALL_NAME" -C ~/nix-install
cd ~/nix-install/nix-"${NIX_VERSION}"-"${SYSTEM}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Installing Nix in Multi User Mode (--daemon) because current user is root..."
  # Root installation must use daemon mode.
  ./install --daemon --yes --no-channel-add
  NIX_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
else
  echo "Installing Nix in Single User Mode (--no-daemon)..."
  echo "Note: implicit sudo access may be requested to create /nix directory if it doesn't exist."
  ./install --no-daemon --yes --no-channel-add
  NIX_PROFILE="$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

rm -rf ~/nix-install ~/"$TARBALL_NAME"

# Configure shell to source Nix profile
echo "Configuring shell environment..."

if [ -f "$NIX_PROFILE" ]; then
  # Add to .zshenv for non-interactive Zsh
  if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ] || [ -f ~/.zshenv ]; then
    if ! grep -q "source $NIX_PROFILE" ~/.zshenv 2>/dev/null; then
      echo "Adding source $NIX_PROFILE to ~/.zshenv"
      echo "if [ -f $NIX_PROFILE ]; then source $NIX_PROFILE; fi" >>~/.zshenv
    fi
  fi
  # Add to .bashrc for Bash
  if ! grep -q "source $NIX_PROFILE" ~/.bashrc 2>/dev/null; then
    echo "Adding source $NIX_PROFILE to ~/.bashrc"
    echo "if [ -f $NIX_PROFILE ]; then source $NIX_PROFILE; fi" >>~/.bashrc
  fi
fi
