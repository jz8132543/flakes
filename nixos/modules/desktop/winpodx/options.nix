{
  config,
  lib,
  pkgs,
  ...
}:

let
  shortcutType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "this WinPodX shortcut" // {
          default = true;
        };

        desktopName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name shown in application menus and desktop entries.";
        };

        genericName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Generic application description (e.g. 'Word Processor').";
        };

        comment = lib.mkOption {
          type = lib.types.str;
          default = "Run ${name} seamlessly via WinPodX";
          description = "Tooltip description shown on hover.";
        };

        slug = lib.mkOption {
          type = lib.types.strMatching "[A-Za-z0-9_-]+";
          default = name;
          description = "Application slug name known to WinPodX (e.g. 'word', 'doubao', 'desktop').";
        };

        executable = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Windows executable for a declarative AppInfo profile; null uses discovery or the built-in desktop command.";
        };

        wmClass = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "FreeRDP WM_CLASS token, also used by StartupWMClass.";
        };

        icon = lib.mkOption {
          type = lib.types.str;
          default = "application-x-executable";
          description = "Icon name from the current icon theme or an absolute path.";
        };

        categories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "Utility" ];
          description = "XDG categories for desktop menu placement.";
        };

        mimeType = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "List of MIME types this application can open.";
        };

        keywords = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Search keywords for desktop application launchers.";
        };

        terminal = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the application should run in a terminal window.";
        };
      };
    }
  );
in
{
  options.programs.winpodx = {
    enable = lib.mkEnableOption "WinPodX Windows Integration (FreeRDP RemoteApp + dockur/windows)" // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "WinPodX package with the first-deployment OEM task and lifecycle protection.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/dockurr/windows@sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea";
      description = "Pinned Windows container image. Changing this does not reuse a different image by retagging it.";
    };

    userName = lib.mkOption {
      type = lib.types.str;
      default = "tippy";
      description = "Host primary user owning the WinPodX storage and sessions.";
    };

    backend = lib.mkOption {
      type = lib.types.enum [
        "podman"
        "docker"
      ];
      default = "podman";
      description = "Container runtime backend for the Windows guest.";
    };

    winVersion = lib.mkOption {
      type = lib.types.str;
      default = "tiny10";
      description = "Windows edition string (e.g. 'tiny10', '10', '11', 'tiny11', 'ltsc10').";
    };

    language = lib.mkOption {
      type = lib.types.str;
      default = "Chinese";
      description = "Initial installation language. Do not change after installation: dockur may back up the disk and reinstall. Tiny10 media may lack a Chinese display-language pack.";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "zh-CN";
      description = "Regional format (date, time, currency).";
    };

    keyboard = lib.mkOption {
      type = lib.types.str;
      default = "zh-CN";
      description = "Keyboard layout for the Windows guest.";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Asia/Shanghai";
      description = "Guest timezone.";
    };

    cpuCores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of CPU cores allocated to the Windows VM.";
    };

    ramGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Memory size allocated to the Windows VM in GiB.";
    };

    diskSize = lib.mkOption {
      type = lib.types.str;
      default = "64G";
      description = "Windows virtual disk size ceiling.";
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.${config.programs.winpodx.userName}.home}/Storage/WinPodX";
      description = "Host directory backing the VM disk image (data.img).";
    };

    rdpPort = lib.mkOption {
      type = lib.types.port;
      default = 3390;
      description = "Host RDP port forwarding to Windows 3389.";
    };

    vncPort = lib.mkOption {
      type = lib.types.port;
      default = 8006;
      description = "Host Web VNC console port.";
    };

    dpi = lib.mkOption {
      type = lib.types.ints.positive;
      default = 150;
      description = "Windows internal DPI scaling percentage (100-300). 150 recommended for 2.5K/4K displays.";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 300;
      description = "Seconds of inactivity before auto-suspending the container (0% CPU). 0 to disable.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start Windows on every tray/login startup. App launches wake it independently of this setting.";
    };

    maxSessions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = "Maximum concurrent RemoteApp sessions allowed via bundled rdprrap multi-session patch.";
    };

    reverseOpen = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable reverse-open: register Linux native apps in Windows 'Open with...' menu.";
    };

    guestUser = lib.mkOption {
      type = lib.types.str;
      default = "Docker";
      description = "Windows account created during unattended installation.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime file supplying the guest password (for example a user-readable sops-nix secret). Otherwise generate one on first deployment.";
    };

    settings = lib.mkOption {
      inherit ((pkgs.formats.toml { })) type;
      default = { };
      description = "Additional upstream TOML settings. Passwords and product keys must use runtime files, not this option.";
    };

    initialDeployment.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Unattended first deployment at login, followed by idempotent Office installation and licensing checks.";
    };

    office = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Office using Microsoft's Office Deployment Tool after the Guest Agent is ready.";
      };
      productId = lib.mkOption {
        type = lib.types.str;
        default = "O365ProPlusRetail";
        description = "ODT product ID matching the purchased license. Microsoft 365 requires licensed account sign-in.";
      };
      channel = lib.mkOption {
        type = lib.types.str;
        default = "Current";
        description = "Office Deployment Tool channel matching the product.";
      };
      language = lib.mkOption {
        type = lib.types.str;
        default = "zh-cn";
        description = "Office installation language.";
      };
      configurationFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional ODT XML override without product keys.";
      };
    };

    activation = {
      method = lib.mkOption {
        type = lib.types.enum [
          "official"
          "mas"
        ];
        default = "official";
        description = "Activation implementation. MAS is opt-in, runs only inside the guest and does not confer a Microsoft license.";
      };
      windowsProductKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime file containing a legally licensed Windows key; never copied into the Nix Store.";
      };
      officeProductKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime file containing a licensed Office volume/retail key compatible with the selected product.";
      };
      requireActivation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Report deployment as incomplete if Windows or enabled Office is not licensed, rather than claiming successful activation.";
      };
    };

    shortcuts = lib.mkOption {
      type = lib.types.attrsOf shortcutType;
      default = { };
      description = "Declarative Windows application shortcuts managed by WinPodX.";
    };
  };

  # 兼容旧配置别名
  imports = [
    (lib.mkAliasOptionModule [ "desktop" "winpodx" ] [ "programs" "winpodx" ])
  ];
}
