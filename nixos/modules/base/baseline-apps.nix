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

  environment.systemPackages =
    with pkgs;
    [
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
      nix-output-monitor
      nix-tree
      age
      backblaze-b2
      # neovim
      p7zip
      unzip
      gnumake
      gcc
      clang
      direnv
      # Tools
      coreutils
      inetutils
      findutils
      dnsutils
      dnsutils
      # lsps
      nil
      nixd
      lua-language-server
      terraform-ls
      vscode-langservers-extracted # css,eslint,html,json,markdown
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.bash-language-server
      dockerfile-language-server
      lua-language-server
      efm-langserver
      shellcheck
      shfmt
      taplo
      yaml-language-server
      # formatters
      eslint_d
      prettierd
      nodePackages.prettier
      nixfmt
      stylua
      alejandra

      nix-output-monitor
      nix-tree
      nurl
      manix
    ]
    ++ (lib.filter lib.isDerivation (lib.attrValues unixtools));
  environment.global-persistence.user.directories = [
    # google ai editor (antigravity)
    ".config/Antigravity"
    ".antigravity"
    ".gemini"
    ".antigravity-server"
  ];

}
