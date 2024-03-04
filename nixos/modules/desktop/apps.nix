{
  config,
  pkgs,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.aria2];
  programs = {
    clash-verge = {
      enable = true;
      autoStart = true;
      tunMode = true;
    };
  };
  environment.systemPackages = with pkgs; [
    qrcp
    # LSP
    nil
    alejandra
    vscode-langservers-extracted
    sumneko-lua-language-server
    stylua
    efm-langserver
    prettierd
    shellcheck
    shfmt
    taplo
    yaml-language-server
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
  environment.global-persistence.user = {
    directories = [
      ".config/clash-verge"
    ];
  };
}
