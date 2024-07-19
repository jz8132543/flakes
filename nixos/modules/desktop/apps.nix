{
  config,
  pkgs,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.aria2];
  programs = {
    # clash-verge = {
    #   enable = true;
    #   autoStart = true;
    #   tunMode = true;
    # };
  };
  environment.systemPackages = with pkgs; [
    qrcp
    # LSP
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
    # nix
    nil
    nix-doc
    nix-melt
    nix-output-monitor
    nix-tree
    nurl
    manix
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
