{ self, inputs, ... }:
with inputs; {
  imports = [ (digga.lib.importExportableModules ../users/modules) ];
  importables = with inputs; rec {
    profiles = digga.lib.rakeLeaves ../users/profiles;
    suites = nixos.lib.fix (suites: {
      base = with profiles; [ direnv git zsh tmux gpg neovim ssh userTools ];
    });
  };
  # users = digga.lib.rakeLeaves ../users/hm;
  users = {
    
  };
}
