{
  description = "Flamework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-2605.url = "github:NixOS/nixpkgs/nixos-26.05";
    # TODO: Remove after Hermes upstream resolves ErikBPF/hermes-flake#77.
    hermes-nixpkgs.url = "github:NixOS/nixpkgs/31ecbaca1bdefa45dffc409f0250bd8039ea0010";
    # LTS is mutable; refresh with: nix flake update --refresh rime-wanxiang-gram
    rime-wanxiang-gram = {
      url = "file+https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram";
      flake = false;
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    nixos-hardware.url = "github:nixos/nixos-hardware";
    linux-surface = {
      url = "github:linux-surface/linux-surface";
      flake = false;
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # kaogong.url = "path:/home/tippy/source/kaogong";
    kaogong.url = "github:jz8132543/kaogong";
    flake-utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
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
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.stable.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
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
    lix = {
      url = "github:lix-project/lix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Keep upstream's locked nixpkgs for the officially cached desktop builds.
    umbriel.url = "github:noctalia-dev/umbriel/cachix";
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
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
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
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
    linyinfeng = {
      url = "github:linyinfeng/nur-packages";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-stable.follows = "blank";
      inputs.devshell.follows = "devshell";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.flake-compat.follows = "flake-compat";
    };
    # Themes
    mactahoe-gtk = {
      url = "github:vinceliuice/MacTahoe-gtk-theme/1e45e19f510edb8cde18fa84d6cd5319f60b086b";
      flake = false;
    };
    mactahoe-icons = {
      url = "github:vinceliuice/MacTahoe-icon-theme/839848b9a8a38a92a6936e30c4abe35cc6f2546d";
      flake = false;
    };
    grub2-themes = {
      url = "github:vinceliuice/grub2-themes/4c5a77125b93f833edc9bf7b14a899faa8ac79c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chinese-fonts-overlay.url = "github:brsvh/chinese-fonts-overlay";
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };
    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
    };
    degoog = {
      url = "github:degoog-org/degoog";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "hermes-nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    paseo = {
      url = "github:getpaseo/paseo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
    omp-flake.url = "github:cernoh/omp-flake";
    grimmory-flake = {
      url = "github:dnaq/booklore-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    winpodx = {
      url = "github:kernalix7/winpodx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    office365 = {
      url = "github:Tombert/office365_flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nectarlink = {
      # Upstream Linux --minimized fix (#336), pending the next tagged release.
      url = "github:thtbee/nectarlink/61972e3ad756e52b72a31ec8a5a5bd90ff256256";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    tcp-brutal = {
      url = "github:HyNetworks/tcp-brutal";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    dde-nixos = {
      url = "github:linuxdeepin/dde-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        config,
        lib,
        ...
      }:
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
        ]
        ++ selfLib.buildModuleList ./flake;
      }
    );
}
