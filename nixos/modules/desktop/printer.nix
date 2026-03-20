{ pkgs, ... }:
{
  services.ipp-usb.enable = true;
  services.printing = {
    enable = true;
    browsing = false;
    browsed.enable = false;
    startWhenNeeded = false;
    webInterface = true;
    drivers = with pkgs; [
      cups-filters
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
