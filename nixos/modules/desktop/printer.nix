{ pkgs, lib, ... }: {
  # The P3301DN advertises a broken IPP-over-USB scanner endpoint and resets
  # during ipp-usb probing; use its P3300DN-compatible USB driver instead.
  services.ipp-usb.enable = false;
  programs.system-config-printer.enable = true;
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
    publish = {
      enable = lib.mkForce null;
      userServices = lib.mkForce null;
    };
    settings.publish = {
      "disable-publishing" = false;
      disable-user-service-publishing = false;
      publish-addresses = true;
    };
  };

  hardware.printers.ensurePrinters = [
    {
      name = "PantumP3301DN";
      description = "Pantum P3301DN";
      deviceUri = "usb://Pantum/P3301DN?serial=CF6L054208";
      model = "Pantum/Pantum P3300DN Series PS.ppd";
      ppdOptions = {
        PageSize = "A4";
        Duplex = "DuplexNoTumble";
      };
    }
  ];
}
