{ config, lib, ... }:

{
  options.programs.winapps = {
    enable = lib.mkEnableOption "WinApps using the upstream Nix package and Windows container" // {
      default = true;
    };

    autopause = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use upstream WinApps idle pause and launch-triggered resume.";
      };
      timeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = "Idle seconds before pausing Windows. Pausing retains guest RAM.";
      };
    };

    discovery = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable application discovery helper service. Manual scanning via 'winapps-scan' or the desktop entry is recommended over periodic timers.";
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "10min";
        description = "Interval between application discovery attempts; paused containers are not awakened.";
      };
    };

    office = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Office with Microsoft's Office Deployment Tool during first guest provisioning.";
      };
      productId = lib.mkOption {
        type = lib.types.str;
        default = "O365ProPlusRetail";
        description = "Licensed Office Deployment Tool product ID. Microsoft 365 requires a licensed account sign-in.";
      };
      channel = lib.mkOption {
        type = lib.types.str;
        default = "Current";
        description = "Office Deployment Tool update channel for the selected product.";
      };
      language = lib.mkOption {
        type = lib.types.str;
        default = "zh-cn";
        description = "Office language ID.";
      };
      configurationFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional Office Deployment Tool XML instead of the generated configuration. Do not put product keys in Nix files.";
      };
    };

    activation = {
      windowsProductKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime host file containing a licensed Windows product key; mounted read-only, never copied into the Nix store.";
      };
      officeProductKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime host file containing a licensed Office key compatible with the deployed product. Subscription Office uses account sign-in instead.";
      };
    };
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
      enable = lib.mkEnableOption "WinApps integration with Rootless Podman (dockurr/windows)" // {
        default = config.programs.winapps.enable;
      };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to start the Podman Windows container at boot.";
      };

      autoSuspend = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pause after boot only after guest provisioning and Office installation report success. Normal idle pause/resume is handled upstream.";
      };

      autoSuspendDelay = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Minimum initialization time before the boot pause, after provisioning succeeds.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3390;
        description = "Host RDP port mapped to Windows VM (defaults to 3390 to avoid conflict with xrdp).";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "Docker";
        description = "Windows username created by dockur/windows. Must match RDP_USER in winapps.conf.";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Windows password created by dockur/windows. Must match RDP_PASS in winapps.conf.";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/dockurr/windows:latest";
        description = "Windows container image. Defaults to dockur/windows:latest.";
      };

      diskSize = lib.mkOption {
        type = lib.types.str;
        default = "64G";
        description = "Size of the Windows virtual disk.";
      };

      ballooning = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable dynamic memory ballooning so dockur/windows can reclaim unused guest RAM under host memory pressure.";
      };

      version = lib.mkOption {
        type = lib.types.str;
        default = "tiny10";
        description = "Windows version to deploy in dockurr/windows (default 'tiny10' for minimal footprint and low resource overhead).";
      };

      language = lib.mkOption {
        type = lib.types.str;
        default = "English";
        description = "Windows display language for first installation.";
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
        default = "${config.users.users.${config.programs.winapps.userName}.home}/Storage/WinApps";
        description = "Host directory where Windows virtual disk is stored.";
      };

      sharedPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.users.users.${config.programs.winapps.userName}.home}/Storage/WinAppsShare";
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
    (lib.mkAliasOptionModule [ "desktop" "winapps" ] [ "programs" "winapps" ])
  ];
}
