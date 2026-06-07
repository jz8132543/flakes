#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PKGS_DIR="$ROOT/pkgs"
SYSTEM="${NIX_UPDATE_SYSTEM:-$(nix eval --impure --raw --expr builtins.currentSystem)}"

if [ -n "${NIX_UPDATE_BIN:-}" ]; then
  read -r -a update_cmd <<<"${NIX_UPDATE_BIN}"
elif command -v nix-update >/dev/null 2>&1; then
  update_cmd=(nix-update)
else
  update_cmd=(nix run nixpkgs#nix-update --)
fi

packages=()
update_args=()
seen_separator=false
include_non_updateable=false

for arg in "$@"; do
  if [ "$arg" = "--all" ]; then
    include_non_updateable=true
    continue
  fi

  if [ "$arg" = "--" ]; then
    seen_separator=true
    continue
  fi

  if [ "$seen_separator" = true ]; then
    update_args+=("$arg")
  else
    packages+=("$arg")
  fi
done

if [ "${#packages[@]}" -eq 0 ]; then
  non_updateable_packages=(
    bbrv1-kmod
    rime-deploy
    rime-user-data
    save-restricted-content-bot-image
    ssh-race
  )

  while IFS= read -r -d '' dir; do
    name="$(basename "$dir")"
    if [ "$include_non_updateable" = false ]; then
      skip=false
      for excluded in "${non_updateable_packages[@]}"; do
        if [ "$name" = "$excluded" ]; then
          skip=true
          break
        fi
      done
      if [ "$skip" = true ]; then
        continue
      fi
    fi
    packages+=("$name")
  done < <(find "$PKGS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '_sources' -print0 | sort -z)
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

failures=0

for pkg in "${packages[@]}"; do
  pkg_dir="$PKGS_DIR/$pkg"
  pkg_file="$pkg_dir/default.nix"

  if [ ! -f "$pkg_file" ]; then
    printf 'skip %s: %s does not exist\n' "$pkg" "$pkg_file" >&2
    failures=$((failures + 1))
    continue
  fi

  wrapper="$tmpdir/$pkg.nix"
  cat >"$wrapper" <<EOF
{ system ? builtins.currentSystem, overlays ? [ ] }:
let
  flake = builtins.getFlake "$ROOT";
  pkgs = import flake.inputs.nixpkgs { inherit system overlays; };
in
{
  "$pkg" = pkgs.callPackage "$pkg_file" { };
}
EOF

  printf 'update %s\n' "$pkg" >&2
  if ! "${update_cmd[@]}" -f "$wrapper" "$pkg" --override-filename "$pkg_file" --system "$SYSTEM" "${update_args[@]}"; then
    printf 'failed %s\n' "$pkg" >&2
    failures=$((failures + 1))
  fi
done

exit "$failures"
