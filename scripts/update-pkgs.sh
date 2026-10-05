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
    save-restricted-content-bot-image
    ssh-race
  )

  while IFS= read -r -d '' dir; do
    rel_path="$(realpath --relative-to="$PKGS_DIR" "$dir")"
    if [ "$rel_path" = "." ]; then
      continue
    fi
    name="$(basename "$dir")"
    if [ "$include_non_updateable" = false ]; then
      skip=false
      for excluded in "${non_updateable_packages[@]}"; do
        if [ "$name" = "$excluded" ] || [ "$rel_path" = "$excluded" ]; then
          skip=true
          break
        fi
      done
      if [ "$skip" = true ]; then
        continue
      fi
    fi
    packages+=("$rel_path")
  done < <(find "$PKGS_DIR" -mindepth 1 -maxdepth 2 -type d ! -name '_sources' ! -name 'pkgs' -exec test -f '{}/default.nix' \; -print0 | sort -z)
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

  # Obsidian 插件特殊更新器（针对多资源：main.js, manifest.json, styles.css）
  if [[ $pkg == obsidian/* ]]; then
    printf 'update %s (Obsidian plugin updater)...\n' "$pkg" >&2
    author="$(grep -oP 'author = "\K[^"]+' "$pkg_file" || true)"
    repo="$(grep -oP 'repo = "\K[^"]+' "$pkg_file" || true)"
    if [ -z "$repo" ]; then repo="$(basename "$pkg")"; fi
    if [ -n "$author" ] && [ -n "$repo" ]; then
      latest_tag="$(curl -sL "https://api.github.com/repos/$author/$repo/releases/latest" | grep -oP '"tag_name": "\K[^"]+' || true)"
      latest_version="${latest_tag#v}"
      current_version="$(grep -oP 'version = "\K[^"]+' "$pkg_file" || true)"
      if [ -n "$latest_version" ] && [ "$latest_version" != "$current_version" ]; then
        echo "Updating $pkg: $current_version -> $latest_version"
        h_main="$(nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_tag/main.js" 2>/dev/null || nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_version/main.js" 2>/dev/null || true)"
        h_manifest="$(nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_tag/manifest.json" 2>/dev/null || nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_version/manifest.json" 2>/dev/null || true)"
        h_css="$(nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_tag/styles.css" 2>/dev/null || nix-prefetch-url "https://github.com/$author/$repo/releases/download/$latest_version/styles.css" 2>/dev/null || true)"

        sri_main="$(nix-hash --to-sri --type sha256 "$h_main" 2>/dev/null || true)"
        sri_manifest="$(nix-hash --to-sri --type sha256 "$h_manifest" 2>/dev/null || true)"

        sed -i "s/version = \"$current_version\"/version = \"$latest_version\"/" "$pkg_file"
        if [ -n "$sri_main" ]; then
          sed -i "s|hashJs = \"[^\"]*\"|hashJs = \"$sri_main\"|" "$pkg_file"
        fi
        if [ -n "$sri_manifest" ]; then
          sed -i "s|hashManifest = \"[^\"]*\"|hashManifest = \"$sri_manifest\"|" "$pkg_file"
        fi
        if [ -n "$h_css" ]; then
          sri_css="$(nix-hash --to-sri --type sha256 "$h_css" 2>/dev/null || true)"
          sed -i "s|hashCss = \"[^\"]*\"|hashCss = \"$sri_css\"|" "$pkg_file"
        fi
        echo "Updated $pkg to $latest_version successfully!"
      else
        echo "$pkg is already up to date ($current_version)."
      fi
    fi
    continue
  fi

  safe_name="$(echo "$pkg" | tr '/' '-')"
  wrapper="$tmpdir/$safe_name.nix"
  attr_name="$(basename "$pkg")"

  cat >"$wrapper" <<EOF
{ system ? builtins.currentSystem, overlays ? [ ] }:
let
  flake = builtins.getFlake "$ROOT";
  pkgs = import flake.inputs.nixpkgs { inherit system overlays; };
in
{
  "$attr_name" = pkgs.callPackage "$pkg_file" { };
}
EOF

  printf 'update %s\n' "$pkg" >&2
  if ! "${update_cmd[@]}" -f "$wrapper" "$attr_name" --override-filename "$pkg_file" --system "$SYSTEM" "${update_args[@]}"; then
    printf 'failed %s\n' "$pkg" >&2
    failures=$((failures + 1))
  fi
done

exit "$failures"
