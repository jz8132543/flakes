{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.winapps;
in
{
  config = lib.mkIf cfg.kvm.enable {
    # Enable libvirtd
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true; # Needed for raw disk access and SMBIOS/SLIC reading
        swtpm.enable = true; # Emulated TPM for Windows 11 compatibility
      };
    };

    # Add the primary user to libvirtd and kvm groups
    users.users."${cfg.userName}".extraGroups = [
      "libvirtd"
      "kvm"
    ];

    # Install Virt-Manager globally
    programs.virt-manager.enable = true;
  };
}
