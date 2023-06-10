{...}: {
  # security.protectKernelImage = true;
  security.sudo = {
    enable = true;
    # execWheelOnly = true;
  };
  security.polkit.enable = true;
}
