{ lib, ... }:

{
  options.desktop.winapps = {
    kvm = {
      enable = lib.mkEnableOption "WinApps integration with KVM (Physical Windows Boot)";

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
    };

    userName = lib.mkOption {
      type = lib.types.str;
      default = "tippy";
      description = "The main user who will run virt-manager and WinApps.";
    };

    enableCdrom = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable physical CD/DVD drive passthrough (/dev/cdrom) to the virtual machines.";
    };
  };

  imports = [
    ./packages.nix
    ./libvirt.nix
    ./vm-definition.nix
    ./docker-windows.nix
  ];
}
