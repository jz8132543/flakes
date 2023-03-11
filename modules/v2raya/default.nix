{ ... }:
{
  services.v2raya.enable = true;

  environment.persistence."/persist".directories = [
    "/etc/v2raya"
    "/root/.local/share/v2ray"
  ];
}
