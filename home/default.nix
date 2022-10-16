{ self, inputs, ... }:
with inputs; {
  imports = [ (digga.lib.importExportableModules ../users/modules) ];
  importables = with inputs; rec {
    profiles = digga.lib.rakeLeaves ../users/profiles;
    suites = with profiles; rec {
      base = [ direnv git zsh gpg neovim ssh userTools ];
      graphical = suites.base ++ (with profiles; [
        graphical.common
        graphical.sway
        graphical.fonts
        graphical.i18n
      ]);
    };
  };
  # users = digga.lib.rakeLeaves ../users/hm;
  users = {
    
  };
}
