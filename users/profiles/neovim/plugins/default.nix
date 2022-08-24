{ lib, ... }: {
  imports = [
    ./aerial.nix
    ./autopairs.nix
    ./bufferline.nix
    ./cmp.nix
    ./comment.nix
    ./dap.nix
    ./dashboard.nix
    ./gitsigns.nix
    ./indent-blankline.nix
    ./lualine.nix
    ./lsp.nix
    ./nvimtree.nix
    ./project.nix
    ./rose-pine.nix
    ./snip.nix
    ./telescope.nix
    ./treesitter.nix
    ./which-key.nix
  ];
}
