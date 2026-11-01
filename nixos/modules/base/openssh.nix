{
  lib,
  config,
  pkgs,
  ...
}:
let
  transport = config.programs.ssh.transport;
  requested = transport.enable && !(lib.elem transport.sourceHost transport.excludedHosts);
  compatible = (transport.package.autoTransportVersion or 0) == 1;
in
{
  options.programs.ssh = {
    # Home Manager reuses this option set, including the standalone defaults.
    transport = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the common automatic terminal SSH transport policy.";
      };
      excludedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "cu" ];
        description = "Source/server host names excluded from automatic SSH transport.";
      };
      sourceHost = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        defaultText = "config.networking.hostName (empty for standalone Home Manager)";
        description = "Local host name used by the source/server exception policy.";
      };
      terminalValidated = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Activate the default interactive terminal entry only after its required transport tests pass.";
      };
      vscodeValidated = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Activate the VS Code adapter only after actual VS Code runtime compatibility tests pass.";
      };
      effectiveEnabled = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        description = "Whether the compatible transport capability is enabled on this source/server.";
      };
      udpPortRange = lib.mkOption {
        type = lib.types.submodule {
          options = {
            from = lib.mkOption {
              type = lib.types.port;
              default = 61001;
            };
            to = lib.mkOption {
              type = lib.types.port;
              default = 61999;
            };
          };
        };
        default = { };
        description = "Inclusive on-demand tsshd UDP port pool shared with clients and routing.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.tsshd;
        defaultText = "pkgs.tsshd";
        description = "Compatible on-demand tsshd server package.";
      };
      clientPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.trzsz-ssh-auto;
        defaultText = "pkgs.trzsz-ssh-auto";
        description = "Transactional auto transport client, without replacing OpenSSH.";
      };
      setupTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "UDP establishment budget in seconds per hop.";
      };
      aliveTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = "Committed connection lifetime after loss of contact, in seconds.";
      };
      mtu = lib.mkOption {
        type = lib.types.ints.between 576 1500;
        default = 1350;
        description = "Conservative UDP transport MTU.";
      };
      heartbeatTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "UDP heartbeat timeout in seconds.";
      };
    };

    enableJumpRouting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable dynamic a-b jump host routing for SSH (jumping via b to a).";
    };

    jumpDomain = lib.mkOption {
      type = lib.types.str;
      default = config.networking.domain;
      defaultText = "config.networking.domain";
      description = "Default domain suffix for jump host resolution.";
    };

    customHosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostname = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Target host name / IP.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 22;
              description = "SSH port.";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "SSH user.";
            };
            addressFamily = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "any"
                  "inet"
                  "inet6"
                ]
              );
              default = null;
              description = "Address family (any, inet, inet6).";
            };
            proxyCommand = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "ProxyCommand for this host.";
            };
          };
        }
      );
      default = {
        cu = {
          hostname = "cu.dora.im";
          port = 50560;
          addressFamily = "inet";
          proxyCommand = "none";
        };
        "cu.dora.im" = {
          hostname = "cu.dora.im";
          port = 50560;
          addressFamily = "inet";
          proxyCommand = "none";
        };
      };
      description = "Custom host entries with non-standard ports or specific settings.";
    };
  };

  config = {
    assertions = [
      {
        assertion = transport.udpPortRange.from <= transport.udpPortRange.to;
        message = "programs.ssh.transport.udpPortRange must be an ordered inclusive range.";
      }
      {
        assertion = !requested || compatible;
        message = "Automatic SSH transport requires a tsshd package with autoTransportVersion = 1.";
      }
    ];
    programs.ssh.transport.effectiveEnabled = requested && compatible;
    environment.systemPackages = lib.mkIf transport.effectiveEnabled [ transport.package ];
    networking.firewall.allowedUDPPortRanges = lib.mkIf transport.effectiveEnabled [
      transport.udpPortRange
    ];

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        AllowTcpForwarding = true;
        AllowStreamLocalForwarding = true;
        PasswordAuthentication = lib.mkForce false;
        KbdInteractiveAuthentication = false;
        IPQoS = "lowdelay throughput";
        VersionAddendum = lib.mkIf transport.effectiveEnabled "tsshd-kcp-auto-v1";
      };
      ports = [
        config.ports.ssh
        22
      ];
      openFirewall = true;
      extraConfig = ''
        ClientAliveInterval 3
        ClientAliveCountMax 6
      '';
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
        }
      ];
    };

    services.fail2ban = {
      enable = true;
      maxretry = 5;
      ignoreIP = [
        "127.0.0.0/8"
        "10.0.0.0/8"
        "100.64.0.0/10"
        "192.168.0.0/16"
      ];
    };

    programs.mosh.enable = true;

    programs.ssh.extraConfig =
      let
        hostBlocks = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: hostCfg: ''
            Host ${name}
              ${lib.optionalString (hostCfg.hostname != null) "HostName ${hostCfg.hostname}"}
              Port ${toString hostCfg.port}
              ${lib.optionalString (hostCfg.user != null) "User ${hostCfg.user}"}
              ${lib.optionalString (hostCfg.addressFamily != null) "AddressFamily ${hostCfg.addressFamily}"}
              ${lib.optionalString (hostCfg.proxyCommand != null) "ProxyCommand ${hostCfg.proxyCommand}"}
          '') config.programs.ssh.customHosts
        );
        jumpBlock = lib.optionalString config.programs.ssh.enableJumpRouting ''
          Host *-* !*.*
            CanonicalizeHostname no
            ProxyCommand sh -c 'target=$(echo %h | cut -d- -f1); jump=$(echo %h | cut -d- -f2); info=$(${pkgs.openssh}/bin/ssh -G "$target" 2>/dev/null); target_host=$(echo "$info" | awk "/^hostname / {print \$2}"); target_port=$(echo "$info" | awk "/^port / {print \$2}"); case "$target_host" in *.*) ;; *) target_host="$target_host.${config.programs.ssh.jumpDomain}" ;; esac; exec ${pkgs.openssh}/bin/ssh -W "$target_host:''${target_port:-22}" "$jump"'
        '';
      in
      lib.mkAfter ''
        ${hostBlocks}
        ${jumpBlock}
      '';
  };
}
