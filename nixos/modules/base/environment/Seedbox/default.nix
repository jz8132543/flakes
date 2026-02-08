{ config, lib, ... }:
with lib;
{
  options.environment.seedbox = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable Seedbox mode.
        This enables automated upload limiting (10MB/s) and PT box whitening
        (proxying tracker traffic through a home connection).
      '';
    };

    proxyHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        The hostname or IP of the home machine running the SOCKS5 proxy (via Tailscale).
      '';
    };

    proxyPort = mkOption {
      type = types.port;
      default = config.ports.seedboxProxyPort;
      description = ''
        The port of the SOCKS5 proxy on the home machine.
      '';
    };
  };
}
