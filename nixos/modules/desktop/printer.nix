{ pkgs, ... }:
{
  services.ipp-usb.enable = true;
  services.printing = {
    enable = true;
    browsing = true;
    browsed.enable = true;
    browsedConf = ''
      CreateIPPPrinterQueues LocalOnly
      DefaultOptions media=A4 sides=two-sided-long-edge
    '';
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
