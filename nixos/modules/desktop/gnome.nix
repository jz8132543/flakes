{
  pkgs,
  lib,
  nixosModules,
  config,
  ...
}:
let
  cfg = config.desktop.kdeconnect;
in
{
  options.desktop.kdeconnect = {
    customDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of custom domains or IPs for KDE Connect default search list";
    };
  };

  imports = [ nixosModules.services.acme ];

  config = {
    # Enable KDE Connect (opens firewall ports 1714-1764 TCP/UDP)
    programs.kdeconnect.enable = true;

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          DiscoverableTimeout = "0";
          Experimental = true;
        };
      };
    };

    services = {
      xserver.enable = true;
      displayManager = {
        gdm = {
          enable = true;
          autoSuspend = false;
        };
        sddm.enable = lib.mkForce false;
      };
      desktopManager = {
        gnome.enable = true;
        plasma6.enable = lib.mkForce false;
      };
      # services.gnome.gnome-remote-desktop.enable = true;
      xrdp = {
        enable = true;
        openFirewall = true;
        defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
      };
      fprintd.enable = true;
      gnome = {
        gnome-browser-connector.enable = true;
        sushi.enable = true;
      };
      gvfs.enable = true;
      logind.settings.Login = {
        # Short-press power key only turns off the screen (handled via GNOME
        # custom keybinding below). Long-press keeps system poweroff as a
        # safety fallback when the system is unresponsive.
        HandlePowerKey = "ignore";
        HandlePowerKeyLongPress = "poweroff";
      };
    };

    environment.systemPackages = with pkgs; [
      weston
      kooha
      pulseaudio
      wl-clipboard
      gnome-power-manager
      gnome-tweaks
      polari
      # TEST
      gnome-session
      gnome-boxes
      devhelp
      dconf-editor
      gnome-sound-recorder
      gnomeExtensions.dash-to-dock
      gnomeExtensions.appindicator
      kdePackages.kdeconnect-kde
      nautilus-python
      # gnomeExtensions.allow-locked-remote-desktop
    ];

    # Let Home Manager own user-level GNOME dconf keys. Keeping locks here makes
    # `home-manager-tippy.service` fail when it tries to write the same keys.
    programs.dconf.enable = true;

    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };

    home-manager.users.tippy = lib.mkIf (cfg.customDomains != [ ]) (
      { lib, ... }: {
        home.activation.setupKdeConnectDomains = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          CONFIG_FILE="$HOME/.config/kdeconnect/config"
          $DRY_RUN_CMD mkdir -p "$HOME/.config/kdeconnect"
          if [ ! -f "$CONFIG_FILE" ] || ! grep -q "^\[General\]" "$CONFIG_FILE"; then
            $DRY_RUN_CMD echo "[General]" >> "$CONFIG_FILE"
          fi
          DOMAINS="${builtins.concatStringsSep "," cfg.customDomains}"
          if grep -q "^customDevices=" "$CONFIG_FILE"; then
            $DRY_RUN_CMD sed -i "s|^customDevices=.*|customDevices=$DOMAINS|" "$CONFIG_FILE"
          else
            $DRY_RUN_CMD sed -i '/^\[General\]/a customDevices='$DOMAINS "$CONFIG_FILE"
          fi
        '';
      }
    );
  };
}
