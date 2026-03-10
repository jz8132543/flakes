{
  config,
  lib,
  modulesPath,
  ...
}:
let
  efiArch = lib.toUpper config.nixpkgs.hostPlatform.efiArch;
in
{
  imports = [ (modulesPath + "/image/repart.nix") ];

  image.repart = {
    name = config.networking.hostName;
    imageSize = "auto";
    sectorSize = 512;

    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOT${efiArch}.EFI".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "EFI";
          SizeMinBytes = "256M";
        };
      };

      "20-root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Format = "btrfs";
          Label = "NIXOS";
          Minimize = "guess";
          Subvolumes = [
            "/rootfs"
            "/nix"
            "/persist"
            "/boot"
            "/swap"
          ];
          MakeDirectories = [
            "/rootfs"
            "/nix"
            "/persist"
            "/boot"
            "/swap"
          ];
        };
      };
    };
  };
}
