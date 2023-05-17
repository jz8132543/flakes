{ config, osConfig, lib, pkgs, ... }:
let
  yq = "${pkgs.yq-go}/bin/yq";
  home = "${config.home.homeDirectory}";
  rimeConfig = ".local/share/fcitx5/rime";
  installationCustom = ''
    sync_dir: "${home}/Syncthing/Main/rime"
    installation_id: "${osConfig.networking.hostName}"
  '';
in
{
  # fcitx
  xdg.configFile."fcitx5" = {
    source = ./_config;
    recursive = true;
  };
  home.activation.removeExistingFcitx5Profile = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${config.xdg.configHome}/fcitx5/profile"
  '';
  # rime
  home.activation.patchRimeInstallation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="${home}/${rimeConfig}/installation.yaml"
    if [ -e "$target" ]; then
      ${yq} eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$target" - --inplace <<EOF
    ${installationCustom}
    EOF
    fi
  '';
  home.file.${rimeConfig} = {
    source = ./_user-data;
    recursive = true;
  };
  # persist
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".config/fcitx5"
      ".config/mozc"
    ];
  };
}
