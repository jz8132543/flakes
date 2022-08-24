{ lib, ... }: {
  imports = [
    ./alpha.nix
    ./autopairs.nix
    ./bufferline.nix
    ./comment.nix
    ./cmp.nix
    ./dap.nix
    ./gitsigns.nix
    ./lualine.nix
    ./mason.nix
    ./nvimtree.nix
    ./project.nix
    ./rose-pine.nix
    ./telescope.nix
    ./treesitter.nix
    ./which-key.nix
  ];
}
