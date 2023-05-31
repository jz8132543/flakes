{
  self,
  pkgs,
  lib,
  config,
  ...
}: let
  CUDA_PATH = pkgs.cudaPackages.cudatoolkit.outPath;
  WSL_MAGIC = "/usr/lib/wsl/lib";
  CUDA_LDPATH = "${
    lib.concatStringsSep ":" [
      WSL_MAGIC
      "/run/opengl-drivers/lib"
      "/run/opengl-drivers-32/lib"
      "${pkgs.cudaPackages.cudatoolkit}/lib"
      "${pkgs.cudaPackages.cudnn}/lib"
    ]
  }:${
    lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib pkgs.cudaPackages.cudatoolkit.lib]
  }";
in {
  imports = [
    self.inputs.nixos-wsl.nixosModules.wsl
  ];
  environment.noXlibs = false;
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    nvidia-docker
  ];
  environment.variables = {
    _CUDA_PATH = CUDA_PATH;
    _CUDA_LDPATH = CUDA_LDPATH;
  };

  wsl = {
    enable = true;
    defaultUser = "tippy";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";

    # Enable native Docker support
    # docker-native.enable = true;
  };
  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
  };

  services.xserver.videoDrivers = ["nvidia"];
  systemd.services.docker.serviceConfig.EnvironmentFile = "/etc/default/docker";
  systemd.services.docker.environment.CUDA_PATH = CUDA_PATH;
  systemd.services.docker.environment.LD_LIBRARY_PATH = CUDA_LDPATH;
  hardware.opengl.enable = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
}
