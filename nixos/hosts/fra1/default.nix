{
  self,
  nixosModules,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.ssh-honeypot.all
    ++ [
      ./hardware-configuration.nix
    ];
}
