{
  config,
  pkgs,
  ...
}:
{
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      config.fileSystems."/nix".device
    ];
  };
  systemd.timers = {
    btrfsBalance = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        AccuracySec = "1d";
        Persistent = true;
      };
    };
    # btrfsDedupe = {
    #   wantedBy = ["timers.target"];
    #   timerConfig = {
    #     OnCalendar = "daily";
    #     AccuracySec = "1d";
    #     Persistent = true;
    #   };
    # };
  };
  systemd.services = {
    btrfsBalance = {
      serviceConfig = {
        Type = "exec";
        Nice = 19;
        IOSchedulingClass = "idle";
        script = ''
          ${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=30,limit=3 /
          ${pkgs.btrfs-progs}/bin/btrfs balance start -musage=30,limit=3 /
        '';
      };
    };
    # btrfsDedupe = {
    #   path = [pkgs.utillinux]; # Used to get # of CPUs
    #   serviceConfig = {
    #     Type = "exec";
    #     IOSchedulingClass = "idle";
    #     RuntimeMaxSec = 7200; # It can hang sometimes
    #     Restart = "on-failure";
    #     ExecStart = "${pkgs.duperemove}/bin/duperemove -rdhA -v --hashfile=/duperemove-hashes.db /";
    #   };
    # };
  };
}
