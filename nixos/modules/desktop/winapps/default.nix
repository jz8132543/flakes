{ lib, ... }:

{
  options.desktop.winapps = {
    kvm = {
      enable = lib.mkEnableOption "WinApps integration with KVM (Physical Windows Boot)";

      enableCdrom = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable physical CD/DVD drive passthrough (/dev/cdrom) to the KVM VM.";
      };

      enableVirtIO = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use VirtIO bus for the primary boot disk in KVM. Set to false to use SATA.";
      };

      extraDisks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of extra physical disks to pass to the KVM VM (e.g., [\"/dev/sda\" \"/dev/sdb\"]).";
      };

      slicAcpiPath = lib.mkOption {
        type = lib.types.str;
        default = "/sys/firmware/acpi/tables/SLIC";
        description = "Path to the SLIC table on the host system to pass through for Windows OEM activation.";
      };
    };

    docker = {
      enable = lib.mkEnableOption "WinApps integration with Docker (dockur/windows)";

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to start the Docker Windows container at boot.";
      };

      enableCdrom = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable physical CD/DVD drive passthrough (/dev/cdrom) to the Docker VM.";
      };

      enableVirtIO = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use VirtIO bus for the primary boot disk in Docker. Set to false to use SATA.";
      };

      extraDisks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of extra physical disks to pass to the Docker VM.";
      };
    };

    podman = {
      enable = lib.mkEnableOption "WinApps integration with Rootless Podman (dockurr/windows)";

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to start the Podman Windows container at boot.";
      };

      autoSuspend = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to automatically suspend (pause) the Windows VM after boot once it has finished starting to save CPU.";
      };

      autoSuspendDelay = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Seconds to wait after Windows RDP port 3389 opens before suspending to let startup tasks finish.";
      };

      version = lib.mkOption {
        type = lib.types.str;
        default = "tiny10";
        description = "Windows version to deploy in dockurr/windows.";
      };

      language = lib.mkOption {
        type = lib.types.str;
        default = "Chinese";
        description = "Windows display language.";
      };

      ramSize = lib.mkOption {
        type = lib.types.str;
        default = "4G";
        description = "RAM allocated to the Windows VM.";
      };

      cpuCores = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "CPU cores allocated to the Windows VM.";
      };

      storagePath = lib.mkOption {
        type = lib.types.str;
        default = "/home/tippy/Storage/WinApps";
        description = "Host directory where Windows virtual disk is stored.";
      };

      sharedPath = lib.mkOption {
        type = lib.types.str;
        default = "/home/tippy/Storage/BottlesShare";
        description = "Shared host directory passed to the container.";
      };
    };

    userName = lib.mkOption {
      type = lib.types.str;
      default = "tippy";
      description = "The main user who will run virt-manager and WinApps.";
    };
  };

  imports = [
    ./packages.nix
    ./libvirt.nix
    ./vm-definition.nix
    ./docker-windows.nix
    ./podman-windows.nix
    ./oem.nix
  ];
}
