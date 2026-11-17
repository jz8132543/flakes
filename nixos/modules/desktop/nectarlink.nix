{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.nectarlink;
  runtimePackages = with pkgs; [
    android-tools
    bluez
    coreutils
    curl
    ethtool
    ffmpeg
    glib
    gst_all_1.gstreamer
    imagemagick
    iproute2
    kmod
    networkmanager
    pipewire
    playerctl
    pulseaudio
    systemd
    util-linux
    wl-clipboard
    wmctrl
    wireplumber
    xclip
    xdotool
    xprintidle
    xprop
    xsel
    xdg-utils
  ];
  gstPlugins = with pkgs; [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    pipewire
  ];
  package = pkgs.symlinkJoin {
    name = "${pkgs.nectarlink.name}-nixos";
    inherit (pkgs.nectarlink) version meta;
    paths = [ pkgs.nectarlink ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    # Keep upstream sources and binaries intact; only supply runtime dependencies.
    postBuild = ''
      for binary in nectarlink-desktop nectarlink; do
        rm "$out/bin/$binary"
        makeBinaryWrapper "${pkgs.nectarlink}/bin/$binary" "$out/bin/$binary" \
          --prefix PATH : "/run/wrappers/bin:${lib.makeBinPath runtimePackages}" \
          --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}" \
          --prefix LD_LIBRARY_PATH : "${
            lib.makeLibraryPath [
              pkgs.libXtst
              pkgs.openh264
            ]
          }"
      done
    '';
  };
  prepareState = pkgs.writeShellScript "nectarlink-prepare-state" ''
    set -eu
    umask 077
    dir="''${XDG_DATA_HOME:-$HOME/.local/share}/Nectarlink"
    ${pkgs.coreutils}/bin/install -d -m 0700 "$dir"
    # The stock app tries these remembered ports first, then falls back if busy.
    printf '%s %s\n' ${toString cfg.port} ${toString cfg.port} > "$dir/port"
    file="$dir/desktop-settings.json"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$dir/.desktop-settings.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    if [ -f "$file" ]; then
      ${pkgs.jq}/bin/jq '. + {
        autoUpdate: false, installUpdates: false, startWithWindows: false,
        language: "zh_CN", awayMode: true, walkthroughCompleted: true
      }' "$file" > "$tmp"
    else
      ${pkgs.jq}/bin/jq -n '{
        autoUpdate: false, installUpdates: false, startWithWindows: false,
        language: "zh_CN", awayMode: true, walkthroughCompleted: true,
        closeToTray: true, autoClipboard: true, clipboardHistory: true,
        suggestClipboardActions: true, syncDnd: true, batteryAlerts: true,
        sendToMenu: true, nectarIsland: true, nectarIslandNotifications: true
      }' > "$tmp"
    fi
    ${pkgs.coreutils}/bin/mv "$tmp" "$file"
  '';
in
{
  options.desktop.nectarlink = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install NectarLink and its desktop, USB, remote-input and virtual-camera integrations.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 7718;
      description = "Preferred UDP port, written to NectarLink's native port state file before startup. The app may use another port if it is occupied.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Unmodified upstream NectarLink package with an outer NixOS runtime wrapper.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.android-tools
    ];
    programs.fuse.enable = true;
    hardware.uinput.enable = true;
    hardware.bluetooth.enable = true;
    services.pipewire = {
      enable = true;
      audio.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    xdg.portal.enable = true;

    boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    boot.kernelModules = [ "v4l2loopback" ];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 card_label="NectarLink Webcam" exclusive_caps=1
    '';
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "nectarlink-device-rules";
        destination = "/lib/udev/rules.d/70-nectarlink.rules";
        text = ''
          KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
          SUBSYSTEM=="video4linux", ATTR{name}=="NectarLink Webcam", TAG+="uaccess"
        '';
      })
    ];

    # Discovery and optional LocalSend interoperability are private-network only.
    # Overlay interface trust belongs to tailscale.nix/easytier.nix, not this app.
    # ADB and the automation API remain localhost-only and need no firewall hole.
    networking.nftables.enable = true;
    networking.firewall.extraInputRules = ''
      ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } udp dport { ${toString cfg.port}, 5353, 53317 } accept
      ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } tcp dport 53317 accept
      ip6 saddr { fc00::/7, fe80::/10 } udp dport { ${toString cfg.port}, 5353, 53317 } accept
      ip6 saddr { fc00::/7, fe80::/10 } tcp dport 53317 accept
    '';

    systemd.user.services.nectarlink-adb = {
      description = "Local ADB server for NectarLink USB connections";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      startLimitIntervalSec = 60;
      startLimitBurst = 3;
      serviceConfig = {
        ExecStart = "${pkgs.android-tools}/bin/adb -L tcp:localhost:5037 server nodaemon";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
      };
    };
    systemd.user.services.nectarlink = {
      description = "NectarLink phone integration";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "nectarlink-adb.service"
      ];
      wants = [ "nectarlink-adb.service" ];
      serviceConfig = {
        ExecStartPre = "${prepareState}";
        ExecStart = "${cfg.package}/bin/nectarlink-desktop --minimized";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "25s";
        UMask = "0077";
      };
    };

    home-manager.sharedModules = [
      {
        home.global-persistence.directories = [
          {
            directory = ".local/share/Nectarlink";
            mode = "0700";
          }
        ];
        xdg.mimeApps.defaultApplications = lib.genAttrs [
          "x-scheme-handler/nectarlink"
          "x-scheme-handler/tel"
          "x-scheme-handler/sms"
          "x-scheme-handler/smsto"
          "x-scheme-handler/mms"
          "x-scheme-handler/mmsto"
        ] (_: [ "nectarlink.desktop" ]);
      }
    ];
  };
}
