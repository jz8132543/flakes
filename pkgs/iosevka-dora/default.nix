{iosevka}:
iosevka.override {
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
}
