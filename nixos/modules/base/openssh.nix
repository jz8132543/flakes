{
  lib,
  config,
  ...
}:
{
  options.programs.ssh = {
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
          };
        }
      );
      default = {
        cu = {
          hostname = "cu.dora.im";
          port = 50560;
        };
        "cu.dora.im" = {
          hostname = "cu.dora.im";
          port = 50560;
        };
      };
      description = "Custom host entries with non-standard ports or specific settings.";
    };
  };

  config = {
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        AllowTcpForwarding = true;
        AllowStreamLocalForwarding = true;
        PasswordAuthentication = lib.mkForce false;
        KbdInteractiveAuthentication = false;
        IPQoS = "lowdelay throughput";
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
          '') config.programs.ssh.customHosts
        );
        jumpBlock = lib.optionalString config.programs.ssh.enableJumpRouting ''
          Host *-* !*.*
            CanonicalizeHostname no
            ProxyCommand sh -c 'target=$(echo %h | cut -d- -f1); jump=$(echo %h | cut -d- -f2); info=$(ssh -G "$target" 2>/dev/null); target_host=$(echo "$info" | awk "/^hostname / {print \$2}"); target_port=$(echo "$info" | awk "/^port / {print \$2}"); case "$target_host" in *.*) ;; *) target_host="$target_host.${config.programs.ssh.jumpDomain}" ;; esac; exec ssh -W "$target_host:''${target_port:-22}" "$jump"'
        '';
      in
      lib.mkAfter ''
        ${hostBlocks}
        ${jumpBlock}
      '';
  };
}
