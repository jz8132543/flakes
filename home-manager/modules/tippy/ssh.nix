{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  sshRaceDomains = [
    "dn42"
    "dora.im"
    "ts"
    "et"
  ];

  customHostSettings = lib.mapAttrs' (
    name: hostCfg:
    lib.nameValuePair name (
      lib.hm.dag.entryBefore [ "*" ] (
        lib.filterAttrs (_: v: v != null) {
          inherit (hostCfg) hostname;
          inherit (hostCfg) port;
          inherit (hostCfg) user;
          inherit (hostCfg) addressFamily;
          inherit (hostCfg) proxyCommand;
        }
      )
    )
  ) (osConfig.programs.ssh.customHosts or { });

  sshJumpRouter = pkgs.writeShellScript "ssh-jump-router" ''
    target="''${1%%-*}"
    jump="''${1#*-}"
    port="$2"
    [ -z "$port" ] || [ "$port" = "%p" ] && port=22

    info=$(ssh -G "$target" 2>/dev/null)
    t_host=$(echo "$info" | awk '/^hostname / {print $2}')
    t_port=$(echo "$info" | awk '/^port / {print $2}')
    [ -n "$t_host" ] && target="$t_host"
    [ -n "$t_port" ] && port="$t_port"

    exec ssh "$jump" "sh -c '
      racer=\$(command -v ssh-race 2>/dev/null || ls -1d /nix/store/*-ssh-race-*/bin/ssh-race 2>/dev/null | tail -n 1)
      if [ -n \"\$racer\" ] && [ -x \"\$racer\" ]; then
        exec \"\$racer\" -domains ${lib.concatStringsSep "," sshRaceDomains} \"$target\" \"$port\"
      fi
      for d in ${lib.concatStringsSep " " sshRaceDomains} \"\"; do
        h=\"$target\"
        [ -n \"\$d\" ] && case \"\$h\" in *.*) ;; *) h=\"\$h.\$d\" ;; esac
        if command -v nc >/dev/null 2>&1 && nc -z -w 1 \"\$h\" \"$port\" 2>/dev/null; then
          exec nc \"\$h\" \"$port\"
        fi
      done
      exec nc \"$target\" \"$port\" 2>/dev/null
    '"
  '';

  jumpRoutingSettings = lib.optionalAttrs (osConfig.programs.ssh.enableJumpRouting or true) {
    "*-* !*.*" = lib.hm.dag.entryBefore [ "*" ] {
      canonicalizeHostname = "no";
      proxyCommand = "${sshJumpRouter} %h %p";
    };
  };
in
with lib.strings;
{
  home.packages = [
    pkgs.ssh-race
  ];

  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      # https://github.com/NixOS/nixpkgs/issues/168322
      # controlPersist = "10m";
      extraOptionOverrides = {
        "StrictHostKeyChecking" = "no";
        "LogLevel" = "ERROR";
        "CanonicalizeHostname" = "yes";
        "CanonicalDomains" = concatStringsSep " " sshRaceDomains;
        # fix kde connection for android
        "HostKeyAlgorithms" = "+ssh-rsa";
      };
      settings =
        customHostSettings
        // jumpRoutingSettings
        // {
          github = {
            host = "github.com";
            user = "git";
            hostname = "ssh.github.com";
            port = 443;
          };
          gitlab = {
            host = "gitlab.com";
            user = "git";
            hostname = "altssh.gitlab.com";
            port = 443;
          };
          raceDomains = lib.hm.dag.entryBefore [ "*" ] {
            match = "canonical final host ${concatMapStringsSep "," (x: "*.${x}") sshRaceDomains}";
            user = "tippy";
            port = osConfig.ports.ssh;
          };
          "*" = {
            checkHostIP = false;
            forwardAgent = true;
            port = osConfig.ports.ssh;
            proxyCommand = "${pkgs.ssh-race}/bin/ssh-race -domains ${concatStringsSep "," sshRaceDomains} %h %p";
            # ForwardX11 = true;
            userKnownHostsFile = "/dev/null";
            serverAliveInterval = 3;
            serverAliveCountMax = 6;
            compression = false;
            controlMaster = "auto";
            controlPath = "~/.ssh/master-%r@%n:%p";
            controlPersist = "10m";
          };
        };
      includes = [
        "config.d/*"
      ];
    };
  };

  home.file.".ssh/config".force = true;

  home.activation.sshConfigPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ssh_dir="$HOME/.ssh"
    if [ -d "$ssh_dir" ]; then
      $DRY_RUN_CMD echo "Fixing permissions for $ssh_dir..."
      $DRY_RUN_CMD chmod 700 "$ssh_dir"

      # Handle config file
      ssh_config="$ssh_dir/config"
      if [ -e "$ssh_config" ]; then
        if [ -L "$ssh_config" ]; then
          $DRY_RUN_CMD echo "Converting $ssh_config from symlink to real file..."
          target=$(readlink -f "$ssh_config")
          $DRY_RUN_CMD rm "$ssh_config"
          $DRY_RUN_CMD cp "$target" "$ssh_config"
        fi
        $DRY_RUN_CMD chmod 600 "$ssh_config"
      fi

      # Handle private keys
      for key in "$ssh_dir"/id_*; do
        if [ -e "$key" ] && [[ ! "$key" == *.pub ]]; then
          if [ -L "$key" ]; then
            $DRY_RUN_CMD echo "Converting private key $key from symlink to real file..."
            target=$(readlink -f "$key")
            $DRY_RUN_CMD rm "$key"
            $DRY_RUN_CMD cp "$target" "$key"
          fi
          $DRY_RUN_CMD chmod 600 "$key"
        fi
      done
    fi
  '';
  home.global-persistence.directories = [
    ".ssh"
  ];
}
