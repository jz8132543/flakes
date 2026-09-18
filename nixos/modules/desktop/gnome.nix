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
              domainCount = builtins.length cfg.customDomains;
              parseAwk = pkgs.writeText "parse-devices.awk" ''
                BEGIN { RS = "objectpath [^/]+/org/gnome/Shell/Extensions/GSConnect/Device/"; }
                NR > 1 {
                  match($0, /^[a-zA-Z0-9_-]+/);
                  dev = substr($0, RSTART, RLENGTH);
                  conn = ($0 ~ /Connected.*<true>/) ? "true" : "false";
                  pair = ($0 ~ /Paired.*<true>/) ? "true" : "false";
                  if (length(dev) > 0) print dev, conn, pair;
                }
              '';
            in
            "${pkgs.writeShellScript "gsconnect-poll" ''
              export PATH="${
                lib.makeBinPath (
                  with pkgs;
                  [
                    coreutils
                    gawk
                    glib
                    tailscale
                  ]
                )
              }:$PATH"

              RUNDIR="''${XDG_RUNTIME_DIR:-/tmp}/gsconnect-helper"
              mkdir -p "$RUNDIR"

              # 1. 快速检查：GSConnect 扩展是否运行（若未启动则在 5ms 内秒退）
              gdbus introspect --session \
                --dest org.gnome.Shell.Extensions.GSConnect \
                --object-path /org/gnome/Shell/Extensions/GSConnect >/dev/null 2>&1 || exit 0

              # 2. 一次性获取所有设备状态
              get_devices_status() {
                gdbus call --session \
                  --dest org.gnome.Shell.Extensions.GSConnect \
                  --object-path /org/gnome/Shell/Extensions/GSConnect \
                  --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
                gawk -f ${parseAwk}
              }

              # 3. 快速通道 (Fast Path)：如果所有配置的设备都已正常连接，直接退出（零开销，<25ms）
              CONNECTED_COUNT=0
              DISCONNECTED_COUNT=0
              while read -r dev conn pair; do
                [ -z "$dev" ] && continue
                if [ "$conn" = "true" ]; then
                  CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
                  rm -f "$RUNDIR/fail-$dev"
                else
                  DISCONNECTED_COUNT=$((DISCONNECTED_COUNT + 1))
                fi
              done < <(get_devices_status)

              if [ "$CONNECTED_COUNT" -ge ${toString domainCount} ] && [ "$DISCONNECTED_COUNT" -eq 0 ]; then
                exit 0
              fi

              # 4. 辅助函数：带缓存的 IP 解析（避免每分钟反复执行 tailscale 命令）
              get_ip() {
                local d="$1"
                local cache="$RUNDIR/ip-$d"
                if [ -f "$cache" ]; then
                  cat "$cache"
                  return
                fi
                local ip
                ip=$(tailscale ip -4 "$d" 2>/dev/null || true)
                if [ -n "$ip" ]; then
                  echo "$ip" > "$cache"
                  echo "$ip"
                fi
              }

              # 5. 向尚未在线或未连通的目标发送发现包
              NEED_WAIT=false
              for domain in ${domainsStr}; do
                ip=$(get_ip "$domain")
                if [ -n "$ip" ]; then
                  gdbus call --session \
                    --dest org.gnome.Shell.Extensions.GSConnect \
                    --object-path /org/gnome/Shell/Extensions/GSConnect \
                    --method org.gtk.Actions.Activate "connect" "[<'lan://''${ip}:1716'>]" "{}" >/dev/null 2>&1 || true
                  NEED_WAIT=true
                fi
              done

              [ "$NEED_WAIT" = "false" ] && exit 0

              # 6. 等待握手建连（放宽至 3 秒以适应 800ms+ 的 DERP 中继延迟）
              sleep 3

              # 7. 再次扫描设备并进行自动配对与死锁自愈
              while read -r dev conn pair; do
                [ -z "$dev" ] && continue

                # 情况 A：在线且未配对 -> 自动发起配对（带 10 分钟防骚扰冷却锁）
                if [ "$conn" = "true" ] && [ "$pair" = "false" ]; then
                  LOCKFILE="$RUNDIR/pair-$dev.lock"
                  NOW=$(date +%s)
                  LAST_TRY=$(cat "$LOCKFILE" 2>/dev/null || echo 0)
                  if [ $((NOW - LAST_TRY)) -gt 600 ]; then
                    echo "$NOW" > "$LOCKFILE"
                    gdbus call --session \
                      --dest org.gnome.Shell.Extensions.GSConnect \
                      --object-path "/org/gnome/Shell/Extensions/GSConnect/Device/$dev" \
                      --method org.gtk.Actions.Activate "pair" "[]" "{}" >/dev/null 2>&1 || true
                  fi

                # 情况 B：成功连接且已配对 -> 清除失败与重试标记
                elif [ "$conn" = "true" ] && [ "$pair" = "true" ]; then
                  rm -f "$RUNDIR/fail-$dev" "$RUNDIR/pair-$dev.lock"

                # 情况 C：电脑记录已配对但连接断开 -> 检测是否发生两端证书不同步死锁
                elif [ "$conn" = "false" ] && [ "$pair" = "true" ]; then
                  FAIL_FILE="$RUNDIR/fail-$dev"
                  count=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
                  count=$((count + 1))
                  echo "$count" > "$FAIL_FILE"

                  # 连续 5 次轮询（约 5 分钟）持续断连时，检测对端 1716 端口是否其实活跃
                  if [ "$count" -ge 5 ]; then
                    DEADLOCK=false
                    for domain in ${domainsStr}; do
                      ip=$(get_ip "$domain")
                      if [ -n "$ip" ] && timeout 1 bash -c "</dev/tcp/$ip/1716" 2>/dev/null; then
                        DEADLOCK=true
                        break
                      fi
                    done

                    # 如果对端 1716 端口存活但持续握手失败断连，说明手机端配对凭据已重置
                    # 自动在后台解除失效配对，以便后续能够自动发起全新配对请求
                    if [ "$DEADLOCK" = "true" ]; then
                      gdbus call --session \
                        --dest org.gnome.Shell.Extensions.GSConnect \
                        --object-path "/org/gnome/Shell/Extensions/GSConnect/Device/$dev" \
                        --method org.gtk.Actions.Activate "unpair" "[]" "{}" >/dev/null 2>&1 || true
                      rm -f "$FAIL_FILE"
                    fi
                  fi
                fi
              done < <(get_devices_status)
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
