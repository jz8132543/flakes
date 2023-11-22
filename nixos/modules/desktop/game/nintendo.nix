{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    yuzu-mainline
  ];
  environment.global-persistence.user = {
    directories = [
    ];
  };
}
