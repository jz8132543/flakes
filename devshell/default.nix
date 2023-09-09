{inputs, ...}: {
  imports = [
    ./terraform
  ];
  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    devshells.default = {
      commands = [
        {
          category = "secrets";
          name = "sops-update-keys";
          help = "update keys for all sops file";
          command = ''
            set -e
            ${pkgs.fd}/bin/fd '.*\.yaml' $PRJ_ROOT/secrets --exec sops updatekeys --yes
          '';
        }
      ];
      packages = with pkgs; [
        # development
        nil
        alejandra
        # nodePackages.vscode-json-languageserver
        vscode-langservers-extracted
        terraform-ls
        tflint
        efm-langserver
        shellcheck
        shfmt
        taplo
        pre-commit

        # secrets
        sops
        age
        ssh-to-age
        age-plugin-yubikey
        # infrastructure
        # nvfetcher
        inputs'.nvfetcher.packages.default
        terraform
      ];
    };
  };
}
