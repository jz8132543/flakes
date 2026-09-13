{
  lib,
  pkgs,
  ...
}:
let
  catppuccinGrub = pkgs.catppuccin-grub.override {
    flavor = "mocha";
  };
in
{
  boot = {
    # 自动选择延时 1 秒
    loader.timeout = lib.mkForce 1;

    # GRUB 引导配置
    loader.grub = {
      # 启用 Catppuccin Mocha 主题
      theme = lib.mkDefault catppuccinGrub;
      font = lib.mkDefault "${catppuccinGrub}/font.pf2";

      # 高分辨率屏幕下原生模式 (auto) 会导致文字和图标极小
      # 设置适宜分辨率（如 1024x768），由硬件/UEFI 缩放显示，使文字与图标比例正常
      gfxmodeEfi = lib.mkDefault "1024x768,auto";
      gfxmodeBios = lib.mkDefault "1024x768";
    };

    # 启用 Plymouth 开机动画，仅配置 Catppuccin Mocha 主题
    plymouth = {
      enable = true;
      theme = "catppuccin-mocha";
      themePackages = [
        (pkgs.catppuccin-plymouth.override {
          variant = "mocha";
        })
      ];
    };
  };
}
