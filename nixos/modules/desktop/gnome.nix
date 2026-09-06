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
      default = [
        "op13.mag"
        "opap.mag"
      ];
      description = "List of custom domains or IPs for KDE Connect default search list";
    };
  };

  imports = [ nixosModules.services.acme ];

  config = {
    # Open firewall ports 1714-1764 TCP/UDP for GSConnect
    networking.firewall = {
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
    };

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

    home-manager.users.tippy = lib.mkIf (cfg.customDomains != [ ]) {
      systemd.user.services.gsconnect-magicdns-poll = {
        Unit = {
          Description = "Poll GSConnect devices via Tailscale MagicDNS";
          After = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart =
            let
              domainsStr = builtins.concatStringsSep " " (map (d: "\"${d}\"") cfg.customDomains);
            in
            "${pkgs.writeShellScript "gsconnect-poll" ''
              for domain in ${domainsStr}; do
                ip=$(${pkgs.tailscale}/bin/tailscale ip -4 "$domain" 2>/dev/null || true)
                if [ -n "$ip" ]; then
                  ${pkgs.glib}/bin/gdbus call --session \
                    --dest org.gnome.Shell.Extensions.GSConnect \
                    --object-path /org/gnome/Shell/Extensions/GSConnect \
                    --method org.gtk.Actions.Activate "connect" "[<'lan://''${ip}:1716'>]" "{}" >/dev/null 2>&1 || true
                fi
              done
            ''}";
        };
      };

      systemd.user.timers.gsconnect-magicdns-poll = {
        Unit = {
          Description = "Poll GSConnect devices via Tailscale MagicDNS";
        };
        Timer = {
          OnBootSec = "1m";
          OnUnitActiveSec = "1m";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
