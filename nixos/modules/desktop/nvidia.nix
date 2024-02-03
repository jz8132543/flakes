{
  pkgs,
  lib,
  config,
  ...
}: let
  CUDA_PATH = pkgs.cudaPackages.cudatoolkit.outPath;
  CUDA_LDPATH = "${
    lib.concatStringsSep ":" [
      "/run/opengl-drivers/lib"
      "/run/opengl-drivers-32/lib"
      "${pkgs.cudaPackages.cudatoolkit}/lib"
      "${pkgs.cudaPackages.cudnn}/lib"
    ]
  }:${
    lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib pkgs.cudaPackages.cudatoolkit.lib]
  }";
in {
  # nixpkgs.config.cudaSupport = true;
  nix.settings = {
    substituters = lib.mkForce [
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
  # CUDA
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    # nvidia-docker
    docker-compose
  ];
  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
    # dockerCompat = true;
  };
  # virtualisation.oci-containers.backend = "podman";
  environment.variables = {
    _CUDA_PATH = CUDA_PATH;
    _CUDA_LDPATH = CUDA_LDPATH;
  };
  systemd.services.docker.environment.CUDA_PATH = CUDA_PATH;
  systemd.services.docker.environment.LD_LIBRARY_PATH = CUDA_LDPATH;
  users.groups.docker.members = config.users.groups.wheel.members;
  # systemd.user.services.podman.environment.CUDA_PATH = CUDA_PATH;
  # systemd.user.services.podman.environment.LD_LIBRARY_PATH = CUDA_LDPATH;
}
