{
  config,
  osConfig,
  pkgs,
  ...
}:
{
  sops.secrets."ssh/id_ed25519".path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub".source = pkgs.writeText "pub" config.lib.self.data.ssh.i;
  home.global-persistence = {
    directories = [
      ".cache/nix"
    ];
  };
  home.sessionVariables =
    if osConfig.networking.fw-proxy.enable then osConfig.networking.fw-proxy.environment else { };
  # home.activation.syncOwnerPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   sync_permissions() {
  #     local target_dir="$1"
  #     if [ -d "$target_dir" ]; then
  #       echo "Syncing permissions in $target_dir..."
  #       find "$target_dir" -mindepth 1 | while read -r item; do
  #         owner_perms=$(stat -c "%u" "$item")
  #         perms=$(stat -c "%a" "$item")
  #         owner_digit="''${perms:0:1}"
  #         new_perms="''${owner_digit}''${perms:1:1}''${owner_digit}"
  #         chmod "$new_perms" "$item" || true
  #       done
  #     fi
  #   }
  #   sync_permissions "/home/tippy/source"
  # '';

  home.packages = with pkgs; [
    duf
    sops
    home-manager
  ];
}
