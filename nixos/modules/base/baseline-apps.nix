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
    nh.enable = true;
    nix-ld = {
      enable = true;
      package = pkgs.nix-ld;
    };
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
    jq
    nmap
    colmena
    deploy-rs
    nixos-anywhere
    # tools
    yq-go
    fd
    age
    # backblaze-b2 # Broken in nixpkgs unstable (docutils dependency conflict)
    # neovim
    p7zip
    unzip
    # Tools
    coreutils
    inetutils
    findutils
    dnsutils

    nixos-install-tools
  ];
  environment.global-persistence = {
    files = [
      # Systemd requires /usr dir to be populated
      # See: https://github.com/nix-community/impermanence/issues/253
      # {
      #   file = "/usr/systemd-placeholder";
      #   inInitrd = true;
      # }
    ];
    user.directories = [
      # google ai editor (antigravity)
      ".config/Antigravity"
      ".antigravity"
      ".gemini"
      ".antigravity-server"
    ];
  };

}
