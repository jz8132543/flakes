{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gnumake
    gcc
    clang
    direnv
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
  ];
}
