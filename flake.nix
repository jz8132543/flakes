{
  description = "Flamework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    latest.url = "github:NixOS/nixpkgs/master";
    release-2505.url = "github:NixOS/nixpkgs/release-25.05";
    nur.url = "github:nix-community/NUR";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    flake-utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";
    systems.url = "github:nix-systems/default";
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvfetcher = {
      url = "github:berberman/nvfetcher";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-compat.follows = "flake-compat";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    haumea = {
      url = "github:nix-community/haumea";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.stable.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gitignore-nix = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.gitignore.follows = "gitignore-nix";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
    nixago = {
      url = "github:nix-community/nixago";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixago-exts.follows = "nixago-exts";
    };
    nixago-exts = {
      url = "github:nix-community/nixago-extensions";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixago.follows = "nixago";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils-plus = {
      url = "github:gytis-ivaskevicius/flake-utils-plus";
      inputs.flake-utils.follows = "flake-utils";
    };
    # poetry2nix = {
    #   url = "github:nix-community/poetry2nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-utils.follows = "flake-utils";
    # };
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-compat.follows = "flake-compat";
    };
    linyinfeng = {
      url = "github:linyinfeng/nur-packages";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-stable.follows = "blank";
      inputs.devshell.follows = "devshell";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.nvfetcher.follows = "nvfetcher";
      inputs.flake-compat.follows = "flake-compat";
    };
    nixpkgs-terraform-providers-bin = {
      url = "github:nix-community/nixpkgs-terraform-providers-bin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixd = {
    #   url = "github:nix-community/nixd";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-parts.follows = "flake-parts";
    # };
    devenv = {
      url = "github:cachix/devenv/latest";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };
    xremap-flake.url = "github:xremap/nix-flake";
    headscale = {
      url = "github:juanfont/headscale";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    tailscale = {
      url = "github:tailscale/tailscale";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-compat.follows = "flake-compat";
    };
    clash2sing-box = {
      url = "github:oluceps/clash2sing-box";
      inputs.flake-utils.follows = "flake-utils";
      inputs.naersk.follows = "naersk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    pastebin = {
      url = "github:linyinfeng/pastebin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    # Themes
    grub2-themes = {
      url = "github:vinceliuice/grub2-themes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    preservation.url = "github:nix-community/preservation";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, lib, ... }:
      let
        selfLib = import ./lib { inherit inputs lib; };
      in
      {
        debug = true;
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        devSystems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        flake.lib = selfLib // {
          inherit (config) systems;
        };
        imports = [
          inputs.flake-parts.flakeModules.easyOverlay
          inputs.devshell.flakeModule
          inputs.treefmt-nix.flakeModule
          inputs.pre-commit-hooks-nix.flakeModule
          inputs.linyinfeng.flakeModules.nixpkgs
          inputs.linyinfeng.flakeModules.passthru
          inputs.linyinfeng.flakeModules.nixago
        ] ++ selfLib.buildModuleList ./flake;
      }
    );
}
