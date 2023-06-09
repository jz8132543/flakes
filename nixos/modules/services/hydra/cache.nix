{
  config,
  pkgs,
  lib,
  ...
}: let
  cacheS3Url = config.lib.self.data.attic.host;
  cacheBucketName = config.lib.self.data.attic.name;
  hydraRootsDir = config.services.hydra.gcRootsDir;
in {
  systemd.services."copy-cache-dora-im@" = {
    script = ''
      export AWS_ACCESS_KEY_ID=$(cat "$CREDENTIALS_DIRECTORY/cache-key-id")
      export AWS_SECRET_ACCESS_KEY=$(cat "$CREDENTIALS_DIRECTORY/cache-access-key")
      root="$1"
      echo "root = $root"

      (
        echo "wait for lock"
        flock 200
        echo "enter critical section"

        nix store sign "$root" --recursive --key-file "$CREDENTIALS_DIRECTORY/signing-key"
        echo "push cache to cahche.dora.im for hydra gcroot: $root"
        # use multipart-upload to avoid cloudflare limit
        nix copy --to "s3://${cacheBucketName}?endpoint=s3.dora.im&multipart-upload=true&parallel-compression=true" "$root" --verbose
      ) 200>/var/lib/cache-dora-im/lock
    '';
    scriptArgs = "%I";
    path = with pkgs; [
      config.nix.package
      fd
      util-linux
    ];
    serviceConfig = {
      User = "hydra";
      Group = "hydra";
      Type = "oneshot";
      StateDirectory = "cache-dora-im";
      LoadCredential = [
        "cache-key-id:${config.sops.secrets."b2/keyID".path}"
        "cache-access-key:${config.sops.secrets."b2/applicationKey".path}"
        "signing-key:${config.sops.secrets."hydra/cache-dora-im".path}"
      ];
    };
    environment = lib.mkMerge [
      {
        HOME = "/var/lib/cache-dora-im";
      }
    ];
  };
  systemd.services."gc-cache-dora-im" = {
    script = ''
      export AWS_ACCESS_KEY_ID=$(cat "$CREDENTIALS_DIRECTORY/cache-key-id")
      export AWS_SECRET_ACCESS_KEY=$(cat "$CREDENTIALS_DIRECTORY/cache-access-key")
      export B2_APPLICATION_KEY_ID=$(cat "$CREDENTIALS_DIRECTORY/cache-key-id")
      export B2_APPLICATION_KEY=$(cat "$CREDENTIALS_DIRECTORY/cache-access-key")

      (
        echo "wait for lock"
        flock 200
        echo "enter critical section"

        echo "canceling all unfinished multipart uploads..."
        backblaze-b2 cancel-all-unfinished-large-files "${cacheBucketName}"

        echo "removing narinfo cache..."
        rm -rf /var/lib/cache-dora-im/.cache

        echo "performing gc..."
        nix-gc-s3 "${cacheBucketName}" --endpoint "${cacheS3Url}" --roots "${hydraRootsDir}" --jobs 10
      ) 200>/var/lib/cache-dora-im/lock
    '';
    path = with pkgs; [
      nix-gc-s3
      config.nix.package
      util-linux
      backblaze-b2
    ];
    serviceConfig = {
      Restart = "on-failure";
      User = "hydra";
      Group = "hydra";
      Type = "oneshot";
      StateDirectory = "cache-dora-im";
      LoadCredential = [
        "cache-key-id:${config.sops.secrets."b2/keyID".path}"
        "cache-access-key:${config.sops.secrets."b2/applicationKey".path}"
      ];
    };
    requiredBy = ["hydra-update-gc-roots.service"];
    after = ["hydra-update-gc-roots.service"];
  };
  sops.secrets = {
    "b2/keyID" = {};
    "b2/applicationKey" = {};
    "hydra/cache-dora-im" = {};
  };
}
