{inputs, ...}: {
  imports = [
    # ./terraform
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
        nodePackages.vscode-json-languageserver
        terraform-ls
        tflint
        nodePackages.bash-language-server
        shfmt
        # secrets
        sops
        age
        ssh-to-age
        age-plugin-yubikey
        # infrastructure
        inputs.terrasops.packages.x86_64-linux.default
        nvfetcher
        (terraform.withPlugins (ps: with ps; [sops hydra]))
      ];
    };
  };
}
