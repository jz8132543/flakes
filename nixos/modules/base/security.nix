{...}: {
  # security.protectKernelImage = true;
  # security.sudo = {
  #   enable = true;
  #   # execWheelOnly = true;
  # };
  security.sudo-rs = {
    enable = true;
    execWheelOnly = true;
    wheelNeedsPassword = false;
  };
  security.polkit.enable = true;
  boot.blacklistedKernelModules = ["virtio_balloon"];
}
