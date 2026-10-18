{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    (bottles.override { removeWarningPopup = true; })
    wineWow64Packages.staging
    winetricks
    protonplus # Blog recommendation: Manage compatibility layers
    protonup-qt # Common native tool to manage Proton/Wine versions
  ];

  # 声明式软链接：建立 ~/.local/share/Steam/compatibilitytools.d/GE-Proton
  # %h 代表当前用户的家目录
  systemd.user.tmpfiles.rules = [
    "d %h/.local/share/Steam/compatibilitytools.d 0755 - - -"
    "L+ %h/.local/share/Steam/compatibilitytools.d/GE-Proton - - - - ${pkgs.proton-ge-bin.steamcompattool}"
  ];

  environment.global-persistence.user.directories = [
    ".local/share/bottles"
    ".config/bottles"
    ".local/share/ms365"
    ".local/share/umu"
    ".local/share/protonplus" # ProtonPlus downloads
    ".config/protonplus" # ProtonPlus configs
  ];
}
