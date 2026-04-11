{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nix-cache-upload;
  inherit (cfg) queueDir;
  queueFile = "${queueDir}/queue";
  lockFile = "${queueDir}/lock";
  snapshotFile = "${queueDir}/queue.snapshot";
  hydraTarget = "root@${cfg.hydraHost}";
  sshOptions = "-i ${cfg.identityFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${toString cfg.sshPort}";
  hookScript = pkgs.writeShellApplication {
    name = "nix-cache-upload-hook";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];

    text = ''
      set -eu

      mkdir -p ${lib.escapeShellArg queueDir}
      exec 9>${lib.escapeShellArg lockFile}
      ${pkgs.util-linux}/bin/flock 9
      for path in $OUT_PATHS; do
        printf '%s\n' "$path" >> ${lib.escapeShellArg queueFile}
      done
    '';
  };
  drainScript = pkgs.writeShellApplication {
    name = "nix-cache-upload-drain";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.openssh
      pkgs.util-linux
    ];

    text = ''
      set -eu
      export NIX_SSHOPTS=${lib.escapeShellArg sshOptions}

      mkdir -p ${lib.escapeShellArg queueDir}
      exec 9>${lib.escapeShellArg lockFile}
      ${pkgs.util-linux}/bin/flock 9

      if [ ! -s ${lib.escapeShellArg queueFile} ]; then
        exit 0
      fi

      rm -f ${lib.escapeShellArg snapshotFile}
      mv ${lib.escapeShellArg queueFile} ${lib.escapeShellArg snapshotFile}
      : > ${lib.escapeShellArg queueFile}
      ${pkgs.util-linux}/bin/flock -u 9

      if [ ! -s ${lib.escapeShellArg snapshotFile} ]; then
        rm -f ${lib.escapeShellArg snapshotFile}
        exit 0
      fi

      if ${pkgs.nix}/bin/nix copy --to ${lib.escapeShellArg "ssh://${hydraTarget}"} --stdin < ${lib.escapeShellArg snapshotFile}; then
        rm -f ${lib.escapeShellArg snapshotFile}
        exit 0
      fi

      exec 9>${lib.escapeShellArg lockFile}
      ${pkgs.util-linux}/bin/flock 9
      cat ${lib.escapeShellArg snapshotFile} >> ${lib.escapeShellArg queueFile}
      rm -f ${lib.escapeShellArg snapshotFile}
    '';
  };
in
{
  options.services.nix-cache-upload = {
    enable = (lib.mkEnableOption "asynchronous Nix cache upload") // {
      default = true;
    };

    hydraHost = lib.mkOption {
      type = lib.types.str;
      default = "cache.dora.im";
      description = "Hydra host used as the upload destination.";
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 1022;
      description = "SSH port used to reach the Hydra host.";
    };

    identityFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.secrets."ssh/id_ed25519".path;
      description = "SSH private key used for cache uploads.";
    };

    queueDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-cache-upload";
      description = "Local queue directory for pending uploads.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${hookScript}";

    systemd.tmpfiles.rules = [
      "d ${queueDir} 0750 root root -"
      "f ${queueFile} 0640 root root -"
    ];

    systemd.services.nix-cache-upload = {
      description = "Drain queued Nix store paths to Hydra";
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${drainScript}";
      };
      after = [ "network-online.target" ];
    };

    systemd.timers.nix-cache-upload = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
        Unit = "nix-cache-upload.service";
      };
    };
  };
}
