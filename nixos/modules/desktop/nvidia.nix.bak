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
  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec "$@"
  '';
in {
  # nixpkgs.config.cudaSupport = true;
  services.xserver.videoDrivers = ["nvidia"];
  systemd.services.nvidia-control-devices = {
    wantedBy = [
      "multi-user.target"
    ];
  };
  hardware.nvidia = {
    modesetting.enable = true;
    # package = config.boot.kernelPackages.nvidiaPackages.production;
    nvidiaSettings = true;
    nvidiaPersistenced = true;
    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
    powerManagement = {
      enable = true;
      finegrained = true;
    };
  };
  nix.settings = {
    substituters = [
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
  # CUDA
  environment.systemPackages = with pkgs; [
    nvidia-offload
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
