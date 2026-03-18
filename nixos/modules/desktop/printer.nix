{ pkgs, ... }:
{
  services.ipp-usb.enable = true;
  services.printing = {
    enable = true;
    browsing = true;
    webInterface = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
      gutenprint
      hplip
      splix
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    openFirewall = true;
  };
}
