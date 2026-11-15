{ pkgs, ... }:
{
  environment.global-persistence = {
    directories = [
      # service state directory
      "/var/lib"
      "/var/db"
    ];
    files = [
      # Impermanence limits stage-2 commit to first boot; do not suppress it here.
      "/etc/machine-id"
    ];
    user.directories = [ ".local/share/nix" ];
  };

  # FirstBoot stays latched for this boot after an in-place identity recovery.
  # Commit is only meaningful for systemd's temporary machine-id mount.
  systemd.services.systemd-machine-id-commit.serviceConfig.ExecCondition =
    pkgs.writeShellScript "machine-id-is-transient" ''
      test "$(${pkgs.coreutils}/bin/stat -f -c %T /etc/machine-id)" = tmpfs
    '';
}
