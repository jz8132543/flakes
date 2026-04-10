{ lib, ... }:
{
  # security.protectKernelImage = true;
  # security.sudo = {
  #   enable = true;
  #   # execWheelOnly = true;
  # };
  # security.sudo-rs = {
  #   enable = true;
  #   execWheelOnly = true;
  #   wheelNeedsPassword = false;
  # };
  # security.pki.certificateFiles = ["${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
  security.polkit.enable = true;
  services.qemuGuest.enable = lib.mkForce false;
  boot.blacklistedKernelModules = [
    "virtio_balloon" # 用于 KVM/QEMU
    "vmw_balloon" # 用于 VMware
    "hv_balloon" # 用于 Hyper-V
    "xen_wballoon" # 用于 Xen
  ];
}
