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
  ];
}
