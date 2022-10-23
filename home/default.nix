{ self, inputs, ... }:
with inputs; {
  imports = [ (digga.lib.importExportableModules ../users/modules) ];
  importables = with inputs; rec {
    profiles = lib.rakeLeaves ../users/profiles;
    suites = nixos.lib.fix (suites: {
      base = with profiles; [ direnv git zsh gpg neovim ssh userTools ];
    });
  };
  # users = digga.lib.rakeLeaves ../users/hm;
  users = {
    
  };
}
