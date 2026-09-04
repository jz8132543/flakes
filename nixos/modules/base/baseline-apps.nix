{ pkgs, inputs, ... }:
{
  imports = [
    inputs.nvf.nixosModules.default
  ];

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

  programs.nvf = {
    enable = true;
    defaultEditor = true;
    enableManpages = true;
    settings = {
      vim = {
        viAlias = false;
        vimAlias = true;
        preventJunkFiles = true;

        theme = {
          enable = true;
          name = "catppuccin";
          style = "mocha";
        };

        statusline.lualine = {
          enable = true;
          setupOpts.options.theme = "catppuccin";
        };

        visuals = {
          nvim-web-devicons.enable = true;
          nvim-cursorline.enable = true;
          cinnamon-nvim.enable = true;
          fidget-nvim.enable = true;
          highlight-undo.enable = true;
          indent-blankline.enable = true;
        };

        lsp = {
          enable = true;
          formatOnSave = true;
          lightbulb.enable = true;
          trouble.enable = true;
        };

        debugger.nvim-dap = {
          enable = true;
          ui.enable = true;
        };

        languages = {
          enableFormat = true;
          enableTreesitter = true;
          enableExtraDiagnostics = true;

          nix.enable = true;
          markdown.enable = true;
          bash.enable = true;
          clang.enable = true;
          cmake.enable = true;
          css.enable = true;
          html.enable = true;
          json.enable = true;
          sql.enable = true;
          go.enable = true;
          lua.enable = true;
          rust = {
            enable = true;
            extensions.crates-nvim.enable = true;
          };
          python.enable = true;
          toml.enable = true;
          docker.enable = true;
          tsx.enable = true;
        };

        autocomplete = {
          nvim-cmp.enable = true;
        };
        snippets.luasnip.enable = true;

        autopairs.nvim-autopairs.enable = true;

        filetree.neo-tree.enable = true;

        tabline.nvimBufferline.enable = true;

        treesitter.context.enable = true;

        binds = {
          whichKey.enable = true;
          cheatsheet.enable = true;
        };

        telescope.enable = true;

        git = {
          enable = true;
          gitsigns.enable = true;
        };

        notify.nvim-notify.enable = true;

        utility = {
          diffview-nvim.enable = true;
          surround.enable = true;
          undotree.enable = true;
          motion = {
            hop.enable = true;
            leap.enable = true;
          };
        };

        notes = {
          todo-comments.enable = true;
        };

        terminal = {
          toggleterm = {
            enable = true;
            lazygit.enable = true;
          };
        };

        ui = {
          borders.enable = true;
          noice.enable = true;
          colorizer.enable = true;
          illuminate.enable = true;
        };

        comments.comment-nvim.enable = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    curlFull
    wget
    fastfetch
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
      ".config/Antigravity IDE"
      ".antigravity"
      ".antigravity-ide"
      ".gemini"
      ".antigravity-server"
    ];
  };

}
