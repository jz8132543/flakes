{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      lib,
      system,
      ...
    }:
    let
      localPackages = (import ../pkgs).packages pkgs;
      mactahoe = import ../lib/mactahoe-packages.nix {
        inherit pkgs;
        gtkSource = inputs.mactahoe-gtk;
        iconsSource = inputs.mactahoe-icons;
      };
      can0LowmemKexec =
        let
          nixosImagesPkgs = inputs.nixos-images.inputs.nixos-unstable.legacyPackages.${system};
        in
        lib.optionalAttrs (system == "x86_64-linux") {
          kexec-installer-can0-lowmem =
            (nixosImagesPkgs.nixos [
              {
                _file = __curPos.file;
                system.kexec-installer.name = "nixos-kexec-installer-can0-lowmem";
                imports = [
                  inputs.nixos-images.nixosModules.kexec-installer
                  inputs.nixos-images.nixosModules.noninteractive
                  ../nixos/hosts/can0/hardware-configuration.nix
                  (
                    { lib, pkgs, ... }:
                    {
                      boot.initrd.compressor = lib.mkForce "gzip";
                      boot.initrd.availableKernelModules = lib.mkForce [
                        "ata_piix"
                        "uhci_hcd"
                        "virtio_pci"
                        "virtio_blk"
                      ];
                      boot.kernelModules = lib.mkForce [ ];
                      boot.supportedFilesystems = lib.mkForce [
                        "ext4"
                        "vfat"
                      ];
                      documentation.enable = lib.mkForce false;
                      documentation.doc.enable = lib.mkForce false;
                      documentation.info.enable = lib.mkForce false;
                      documentation.man.enable = lib.mkForce false;
                      documentation.nixos.enable = lib.mkForce false;
                      environment.defaultPackages = lib.mkForce [
                        pkgs.parted
                        pkgs.gptfdisk
                        pkgs.e2fsprogs
                      ];
                      environment.systemPackages = lib.mkForce [ ];
                      hardware.enableRedistributableFirmware = lib.mkForce false;
                      networking.firewall.enable = lib.mkForce false;
                      networking.networkmanager.enable = lib.mkForce false;
                      programs.command-not-found.enable = lib.mkForce false;
                      services.logrotate.enable = lib.mkForce false;
                      services.udisks2.enable = lib.mkForce false;
                      services.journald.extraConfig = lib.mkForce ''
                        SystemMaxUse=8M
                        RuntimeMaxUse=8M
                      '';
                      system.extraDependencies = lib.mkForce [ ];
                      xdg.autostart.enable = lib.mkForce false;
                      xdg.icons.enable = lib.mkForce false;
                      xdg.mime.enable = lib.mkForce false;
                      xdg.sounds.enable = lib.mkForce false;
                    }
                  )
                ];
              }
            ]).config.system.build.kexecInstallerTarball;
        };
    in
    {
      packages = {
        inherit (pkgs) nixos-anywhere;
        mactahoe-gtk = mactahoe.gtk;
        mactahoe-gtk-visual = mactahoe.gtkVisual;
        mactahoe-icons = mactahoe.icons;
        mactahoe-cursors = mactahoe.cursors;
        mactahoe-firefox = mactahoe.firefox;
        mactahoe-wallpaper = mactahoe.wallpaper;
        wallpaper-hdr = pkgs.wallpaper.hdr;
        mactahoe-gdm = mactahoe.gdmTheme;
        inherit (localPackages)
          corplink-rs
          fluxdown
          hdr-wallpaper
          linglong-store
          ssh-race
          trzsz-ssh-auto
          tsshd
          ;
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        inherit (localPackages) bitwig-studio;
        bitwig-studio-patched = localPackages.bitwig-studio.override { applyJarPatch = true; };
      }
      // can0LowmemKexec;
      checks = lib.mapAttrs' (name: p: lib.nameValuePair "package/${name}" p) self'.packages // {
        mactahoe-assets-test =
          pkgs.runCommand "mactahoe-assets-test"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.glib
              ];
            }
            ''
              python3 -B ${../tests/mactahoe-assets-test.py} \
                --gtk ${mactahoe.gtk} --gtk-visual ${mactahoe.gtkVisual} --icons ${mactahoe.icons} \
                --cursors ${mactahoe.cursors} --wallpaper ${mactahoe.wallpaper} --firefox ${mactahoe.firefox} \
                --gtk-source ${inputs.mactahoe-gtk} --icons-source ${inputs.mactahoe-icons} \
                --gdm-theme ${mactahoe.gdmTheme} --gnome-shell ${pkgs.gnome-shell}
              touch "$out"
            '';
      };
    };
}
