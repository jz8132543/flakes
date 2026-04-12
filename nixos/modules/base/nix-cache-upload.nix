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
  hydraStoreUri = "ssh-ng://${hydraTarget}" + lib.optionalString cfg.sshCompression "?compress=true";
  signKeyFile = config.sops.secrets."hydra/cache-dora-im".path;
  sshOptions = "-i ${cfg.identityFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${toString cfg.sshPort}";
  drainScript = pkgs.writeShellScript "nix-cache-upload-drain" ''
    set +e

    export NIX_SSHOPTS=${lib.escapeShellArg sshOptions}

    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg queueDir} || exit 0
    exec 9>${lib.escapeShellArg lockFile} || exit 0
    ${pkgs.util-linux}/bin/flock 9 || exit 0

    if [ ! -s ${lib.escapeShellArg queueFile} ]; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg snapshotFile} || true
    ${pkgs.coreutils}/bin/mv ${lib.escapeShellArg queueFile} ${lib.escapeShellArg snapshotFile} || exit 0
    : > ${lib.escapeShellArg queueFile}
    ${pkgs.util-linux}/bin/flock -u 9 || true

    if [ ! -s ${lib.escapeShellArg snapshotFile} ]; then
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg snapshotFile} || true
      exit 0
    fi

    totalCount="$(${pkgs.coreutils}/bin/wc -l < ${lib.escapeShellArg snapshotFile} | ${pkgs.coreutils}/bin/tr -d ' ' )"
    validPathsFile="${queueDir}/valid"
    invalidPathsFile="${queueDir}/invalid"
    ${pkgs.coreutils}/bin/rm -f "$validPathsFile" "$invalidPathsFile" || true

    echo "nix-cache-upload: current system paths:"
    ${pkgs.coreutils}/bin/cat ${lib.escapeShellArg snapshotFile}
    echo "nix-cache-upload: total queued path(s)=''${totalCount}"

    transferredCount=0
    failedCount=0
    failedPathsFile="${queueDir}/failed"
    ${pkgs.coreutils}/bin/rm -f "$failedPathsFile" || true

    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! ${pkgs.nix}/bin/nix path-info "$path" >/dev/null 2>&1; then
        echo "nix-cache-upload: skipping invalid path $path"
        failedCount=$((failedCount + 1))
        ${pkgs.coreutils}/bin/printf '%s\n' "$path" >> "$invalidPathsFile"
        continue
      fi
      ${pkgs.coreutils}/bin/printf '%s\n' "$path" >> "$validPathsFile"
    done < ${lib.escapeShellArg snapshotFile}

    transferCount="$(${pkgs.coreutils}/bin/wc -l < "$validPathsFile" | ${pkgs.coreutils}/bin/tr -d ' ' )"
    echo "nix-cache-upload: need to transfer ''${transferCount} path(s)"
    echo "nix-cache-upload: starting transfer"

    while IFS= read -r path; do
      [ -n "$path" ] || continue
      echo "nix-cache-upload: signing $path"
      if ! ${pkgs.nix}/bin/nix store sign --key-file ${lib.escapeShellArg signKeyFile} --recursive "$path"; then
        failedCount=$((failedCount + 1))
        ${pkgs.coreutils}/bin/printf '%s\n' "$path" >> "$failedPathsFile"
        continue
      fi
      echo "nix-cache-upload: transferring $path"
      if ${pkgs.nix}/bin/nix copy --substitute-on-destination --to ${lib.escapeShellArg hydraStoreUri} "$path"; then
        transferredCount=$((transferredCount + 1))
      else
        failedCount=$((failedCount + 1))
        ${pkgs.coreutils}/bin/printf '%s\n' "$path" >> "$failedPathsFile"
      fi
    done < "$validPathsFile"

    ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg snapshotFile} || true
    ${pkgs.coreutils}/bin/rm -f "$validPathsFile" "$invalidPathsFile" || true

    if [ -s "$failedPathsFile" ]; then
      exec 9>${lib.escapeShellArg lockFile} || exit 0
      ${pkgs.util-linux}/bin/flock 9 || exit 0
      ${pkgs.coreutils}/bin/cat "$failedPathsFile" >> ${lib.escapeShellArg queueFile} || true
      ${pkgs.coreutils}/bin/rm -f "$failedPathsFile" || true
      ${pkgs.util-linux}/bin/flock -u 9 || true
    else
      ${pkgs.coreutils}/bin/rm -f "$failedPathsFile" || true
    fi

    echo "nix-cache-upload: result transferred=$transferredCount failed=$failedCount"
    exit 0
  '';
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

    sshCompression = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH compression for cache uploads.";
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
    # nix.settings.post-build-hook = "${hookScript}";
    nix.settings.secret-key-files = [ config.sops.secrets."hydra/cache-dora-im".path ];

    systemd.tmpfiles.rules = [
      "d ${queueDir} 0750 root root -"
      "f ${queueFile} 0640 root root -"
    ];

    sops.secrets."hydra/cache-dora-im" = {
      mode = "0440";
    };

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
        OnBootSec = "5m";
        OnUnitActiveSec = "5m";
        Unit = "nix-cache-upload.service";
      };
    };
  };
}
