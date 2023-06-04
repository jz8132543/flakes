{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-nightly;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/nvim"
      ".config/nvim"
      # ".config/coc"
    ];
  };
  home.packages = with pkgs; [
    unzip
  ];
}
