{
  needProxy ? false,
  xrayPort ? 8555,
  proxyHosts ? [
    "nue0.dora.im"
    "tyo0.dora.im"
    "sjc0.dora.im"
  ],
  serverName ? "assets.msn.com",
  ss ? false,
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  useHealthCheckedBalancer = needProxy && builtins.length proxyHosts > 1;
in
{
  sops.secrets = {
    "xray/uuid" = {
      mode = "0444";
    };
    "xray/private_key" = {
      mode = "0444";
    };
    "xray/short_id" = {
      mode = "0444";
    };
    "xray/cf_tunnel_token" = {
      mode = "0444";
    };
    "xray/public_key" = {
      mode = "0444";
    };
  };

  # 2. 使用 Template 动态生成 sing-box config.json
  # 配置文件位于 /run/secrets/rendered/，不进入 nix store
  sops.templates."sing-box-config.json" = {
    mode = "0444";
    restartUnits = [ "sing-box.service" ];
    content = builtins.toJSON {
      log = {
        disabled = false;
        level = if config.environment.minimal or false then "warn" else "info";
        timestamp = true;
      };

      inbounds =
        if ss then
          [
            {
              type = "shadowsocks";
              tag = "ss-in";
              listen = "::";
              listen_port = xrayPort;
              method = "2022-blake3-aes-128-gcm";
              password = config.sops.placeholder."xray/uuid";
            }
          ]
        else
          [
            {
              type = "vless";
              tag = "vless-in";
              listen = "::";
              listen_port = xrayPort;
              users = [
                {
                  name = "default";
                  uuid = config.sops.placeholder."xray/uuid";
                  flow = "xtls-rprx-vision";
                }
              ];
              tls = {
                enabled = true;
                server_name = serverName;
                reality = {
                  enabled = true;
                  handshake = {
                    server = serverName;
                    server_port = 443;
                  };
                  private_key = config.sops.placeholder."xray/private_key";
                  short_id = [
                    config.sops.placeholder."xray/short_id"
                  ];
                };
              };
            }
          ];

      # 极致精简出站：纯 direct 直连，无冗余封装
      outbounds = [
        {
          type = "direct";
          tag = "direct";
        }
      ]
      ++ lib.optionals needProxy (
        (lib.imap0 (i: host: {
          tag = "proxy-${toString i}";
          type = "vless";
          server = host;
          server_port = 8555;
          uuid = config.sops.placeholder."xray/uuid";
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = serverName;
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
            reality = {
              enabled = true;
              public_key = config.sops.placeholder."xray/public_key";
              short_id = config.sops.placeholder."xray/short_id";
            };
          };
        }) proxyHosts)
        ++ lib.optionals useHealthCheckedBalancer [
          {
            type = "urltest";
            tag = "proxy-balancer";
            outbounds = lib.imap0 (i: _: "proxy-${toString i}") proxyHosts;
            url = "https://cp.cloudflare.com/generate_204";
            interval = "1m";
          }
        ]
      );

      # 服务端路由优化：
      # 无需代理时留空（无 rules，默认走第一个出站 direct 直出，零 GeoIP/GeoSite 规则集与解析开销）
      # 需要代理时仅使用纯内存前缀后缀匹配，不加载庞大的外部数据库
      route = lib.optionalAttrs needProxy {
        rules = [
          {
            domain_suffix = [
              "skk.moe"
              "openai.com"
              "chatgpt.com"
              "oaistatic.com"
              "oaiusercontent.com"
              "claude.ai"
              "anthropic.com"
            ];
            outbound = if useHealthCheckedBalancer then "proxy-balancer" else "proxy-0";
          }
        ];
        final = "direct";
      };
    };
  };

  # 3. 启用 Sing-box 服务并显式停用老旧的 Xray 服务
  services.sing-box = {
    enable = true;
  };
  services.xray.enable = lib.mkForce false;

  # 4. 针对弱机（1CPU/256M 内存）深度调优 systemd 服务参数
  systemd.services.sing-box = {
    startLimitIntervalSec = lib.mkForce 0;
    serviceConfig = {
      ExecStart = lib.mkForce [
        ""
        "${lib.getExe pkgs.sing-box} -D /var/lib/sing-box run -c ${
          config.sops.templates."sing-box-config.json".path
        }"
      ];
      Restart = lib.mkForce "on-failure";
      RestartSec = "2s";
      MemoryMax = lib.mkDefault "192M";
      MemoryHigh = lib.mkDefault "150M";
      OOMScoreAdjust = lib.mkDefault (-500);
    };
    environment = {
      # 激进 GC 控制内存上限，避免低内存 VPS OOM
      GOGC = lib.mkDefault "50";
      GOMEMLIMIT = lib.mkDefault "128MiB";
    };
  };

  # 5. Traefik SNI Passthrough 保持对接
  services.traefik.dynamicConfigOptions.tcp = {
    routers.xray = {
      entryPoints = [
        "https"
        "https-alt"
      ];
      service = "xray";
      tls.passthrough = true;
      rule = "HostSNI(`${serverName}`)";
    };

    services.xray.loadbalancer.servers = [ { address = "127.0.0.1:${toString xrayPort}"; } ];
  };

  # 6. 定时重启
  systemd.timers = {
    proxy-restart = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        AccuracySec = "1s";
        Persistent = true;
      };
    };
  };
  systemd.services.proxy-restart = {
    description = "Trigger to restart proxy service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart sing-box.service";
    };
  };

  networking.firewall.allowedTCPPorts = [
    8443
    8444
    xrayPort
  ];
  networking.firewall.allowedUDPPorts = [
    8443
    8444
    xrayPort
  ];
}
