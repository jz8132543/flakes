{pkgs, ...}: {
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

    fuse = {
      mountMax = 32767;
      userAllowOther = true;
    };
  };

  environment.systemPackages = with pkgs; [
    nixVersions.unstable
    curlFull
    wget
    neofetch
    screen
    tcpdump
    wireguard-tools
    openssl
    lsof
    vim
    dig
    whois
    expect
    iperf
    nmap
    colmena
    deploy-rs
  ];
}
