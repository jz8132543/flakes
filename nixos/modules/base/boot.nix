{ lib, ... }:
{
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  boot = {
    initrd.systemd.enable = true;
    tmp = {
      cleanOnBoot = true;
      useTmpfs = false;
    };
    kernelParams = [
      "panic=1"
      "boot.panic_on_fail" # Troubleshooting
      "sysrq_always_enabled=1" # SysRQ
      "random.trust_cpu=on" # speed up random seed

      # Performence Improvement
      "nowatchdog"
      "mitigations=off"
    ];
  };
}
