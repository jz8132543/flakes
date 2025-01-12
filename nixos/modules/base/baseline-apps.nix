{ pkgs, ... }:
{
  # Git (Global)
  programs.git = {
    enable = true;
    config = {
      init = {
        defaultBranch = "main";
      };
      core = {
        editor = "vim";
      };
    };
  };

  # Tmux
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    keyMode = "vi";
    escapeTime = 10;
  };

  programs = {
    bash.vteIntegration = true;
    mosh.enable = true;
    mtr.enable = true;
    traceroute.enable = true;
    # neovim = {
    #   enable = true;
    #   defaultEditor = true;
    #   vimAlias = true;
    #   viAlias = false;
    # };
    fuse = {
      mountMax = 32767;
      userAllowOther = true;
    };
  };

  environment.systemPackages = with pkgs; [
    curlFull
    wget
    neofetch
    screen
    tcpdump
    wireguard-tools
    openssl
    gptfdisk
    lsof
    vim
    dig
    whois
    netcat-openbsd
    expect
    iperf
    nmap
    colmena
    deploy-rs
    # tools
    yq-go
    fd
    nix-output-monitor
    nix-tree
    # # neovim
    # unzip
    # gnumake
    # luajit
    # luaPackages.lua
    # luajitPackages.luarocks
    # luajitPackages.magick
    # gcc
  ];
}
