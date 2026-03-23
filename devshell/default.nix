{ pkgs, ... }:
{
  imports = [
    ./terraform.nix
    ./boot-sd.nix
    ./patches.nix
    ./prepare
  ];
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePackages = [ "terraform" ];
  };
  devshells.default = {
    commands = [
      {
        name = "colmena-bin";
        category = "deploy";
        help = "Upstream colmena binary";
        command = ''
          exec ${pkgs.colmena}/bin/colmena "$@"
        '';
      }
      {
        name = "colmena";
        category = "deploy";
        help = "Wrapper around colmena that defaults to ./hive.nix";
        command = ''
          run_colmena() {
            ${pkgs.colmena}/bin/colmena "$@" 2> >(
              awk '
                skip {
                  if ($0 ~ /^• Added input / || $0 ~ /^    / || $0 == "") next;
                  skip = 0;
                }
                index($0, "warning: not writing modified lock file of flake ") == 1 && index($0, "path:/tmp/colmena-assets-") > 0 {
                  skip = 1;
                  next;
                }
                { print }
              ' >&2
            )
          }

          if (($# > 0)); then
            case "$1" in
              -f|--config)
                run_colmena --impure "$@"
                exit $?
                ;;
            esac
          fi

          run_colmena --impure -f "''${PRJ_ROOT:-$(pwd)}/hive.nix" "$@"
        '';
      }
      {
        package = pkgs.sops;
        category = "secrets";
      }
      {
        category = "secrets";
        name = "sops-update-keys";
        help = "update keys for all sops file";
        command = ''
          ${pkgs.fd}/bin/fd '.*\.yaml' $PRJ_ROOT/secrets --exec sops updatekeys --yes
        '';
      }
      {
        package = pkgs.age;
        category = "secrets";
      }
      {
        package = pkgs.age-plugin-yubikey;
        category = "secrets";
      }
      {
        package = pkgs.ssh-to-age;
        category = "secrets";
      }
    ];
    packages = with pkgs; [
      nil
      alejandra
      vscode-langservers-extracted
      yaml-language-server
      terraform-ls
      tflint
      efm-langserver
      shellcheck
      shfmt
      taplo

      terraform
      nvfetcher
      # backblaze-b2

      ruby
      minio-client
    ];
  };
}
