{
  lib,
  pkgs,
  ...
}:
{
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      # TODO nix flake show broken due to IFD
      # ms-vscode.cpptools
    ];
  };

  home.activation.patchVSCodeServer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.vscode-server"
    ${pkgs.findutils}/bin/find "$HOME/.vscode-server" -maxdepth 3 -name node -exec $DRY_RUN_CMD ln -sf $VERBOSE_ARG ${pkgs.nodejs}/bin/node {} \;
  '';

  home.global-persistence.directories = [
    ".vscode"
    ".vscode-server"
    ".config/Code"
  ];
}
