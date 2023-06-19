{
  pkgs,
  config,
  ...
}: let
  iosevka-dora = pkgs.iosevka.override {
    privateBuildPlan = {
      family = "Iosevka Doraemon";
      spacing = "fontconfig-mono";
      serifs = "slab";
      # no need to export character variants and stylistic set
      no-cv-ss = "true";
      ligations = {
        inherits = "haskell";
      };
    };
    set = "dora";
  };
  iosevka-dora-nf = pkgs.stdenv.mkDerivation {
    name = "iosevka-dora-nf";
    src = iosevka-dora;
    nativeBuildInputs = with pkgs; [
      nerd-font-patcher
    ];
    enableParallelBuilding = true;
    unpackPhase = ''
      mkdir -p fonts
      cp -r $src/share/fonts/truetype/. ./fonts/
      chmod u+w -R ./fonts
    '';
    postPatch = ''
      cp ${config.lib.self.path}/conf/font/NerdFontMakefile ./Makefile
    '';
  };
in {
  fonts.fonts = with pkgs; [
    noto-fonts-emoji

    source-serif
    source-han-serif
    source-sans
    source-han-sans
    source-code-pro

    open-sans
    liberation_ttf
    wqy_zenhei
    wqy_microhei

    jetbrains-mono
    iosevka-dora
    iosevka-dora-nf
    font-awesome
    powerline-fonts
    sarasa-gothic
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Source Sans 3"
      "Source Han Sans SC"
      "Source Han Sans TC"
      "Source Han Sans HW"
      "Source Han Sans K"
    ];
    serif = [
      "Source Serif 4"
      "Source Han Serif SC"
      "Source Han Serif TC"
      "Source Han Serif HW"
      "Source Han Serif K"
    ];
    monospace = [
      "Iosevka Doraemon"
      "Sarasa Mono Slab SC"
    ];
    emoji = [
      "Noto Color Emoji"
    ];
  };
}

