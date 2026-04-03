{ pkgs, ... }:
{
  services.ipp-usb.enable = true;
  services.printing = {
    enable = true;
    browsing = true;
    browsed.enable = true;
    browsedConf = ''
      CreateIPPPrinterQueues LocalOnly
      DefaultOptions media=A4 PageSize=A4 sides=two-sided-long-edge Duplex=DuplexNoTumble
    '';
    startWhenNeeded = false;
    webInterface = true;
    drivers = with pkgs; [
      cups-filters
      gutenprint
      hplip
      splix
      pantum-driver
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    openFirewall = true;
  };

  # hardware.printers.ensurePrinters = [
  #   {
  #     name = "Pantum3301DN";
  #     description = "Pantum P3301DN";
  #     deviceUri = "usb://Pantum/P3301DN";
  #     model = "drv:///hp/hpcups.drv/hp-business_inkjet_3000-pcl3.ppd";
  #     ppdOptions = {
  #       PageSize = "A4";
  #       Duplex = "DuplexNoTumble";
  #     };
  #   }
  # ];
}
