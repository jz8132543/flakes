{ ... }:
{
  services.xray = {
    enable = true;
    settingsFile = "/etc/xray/config.json";
  };

  environment.persistence."/nix/persist".directories = [
    "/etc/xray"
  ];
}

