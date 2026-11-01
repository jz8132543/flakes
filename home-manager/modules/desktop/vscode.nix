{
  lib,
  pkgs,
  config,
  ...
}:
let
  transport = config.programs.ssh.transport;
  sshAdapter = pkgs.writeScriptBin "vscode-ssh-auto" (
    "#!${pkgs.python3}/bin/python3\n"
    +
      builtins.replaceStrings
        [ "@openssh@" "@tssh@" ]
        [ "${pkgs.openssh}/bin/ssh" "${transport.clientPackage}/bin/tssh" ]
        (builtins.readFile ./vscode-ssh-adapter.py)
  );
in
{
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      # TODO nix flake show broken due to IFD
      # ms-vscode.cpptools
    ];
    profiles.default.userSettings."remote.SSH.path" = lib.mkIf (
      transport.effectiveEnabled && transport.vscodeValidated
    ) "${sshAdapter}/bin/vscode-ssh-auto";
  };

  home.activation.patchVSCodeServer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.vscode-server"
    ${pkgs.findutils}/bin/find "$HOME/.vscode-server" -maxdepth 3 -name node -exec $DRY_RUN_CMD ln -sf $VERBOSE_ARG ${pkgs.nodejs}/bin/node {} \;
  '';

  home.global-persistence.directories = [
    ".vscode"
    ".vscode-server"
    ".config/Code"
    ".vscode-shared"
  ];
}
