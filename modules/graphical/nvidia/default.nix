{ pkgs, lib, config, ... }:

let
  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec "$@"
  '';
  buildScript = ''nvcc -o "$1".bin "$1" -I ${pkgs.cudatoolkit}/include -ldir ${pkgs.cudatoolkit}/nvvm/libdevice/ -L ${pkgs.cudatoolkit}/lib -L ${pkgs.cudatoolkit.lib}/lib --dont-use-profile -G --std=c++11 -rdc=true -gencode=arch=compute_61,code=sm_61 -lcudadevrt patchelf --set-rpath "/run/opengl-driver/lib:"$(patchelf --print-rpath "$1".bin) "$1".bin
'';
  cudaCompile = pkgs.writeScriptBin "cudaCompile" ''
    #!${pkgs.stdenv.shell}
    ${buildScript}
  '';
in
lib.mkIf config.environment.graphical.enable {
  environment.systemPackages = with pkgs; [
    nvidia-offload
    cudatoolkit
    cudaCompile
    python3
    python3Packages.pytorch-bin
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "python-2.7.18.6"
  ];

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.prime = {
    offload.enable = true;

    # Bus ID of the Intel GPU. You can find it using lspci, either under 3D or VGA
    intelBusId = "PCI:0:2:0";

    # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
    nvidiaBusId = "PCI:2:0:0";
  };
}
