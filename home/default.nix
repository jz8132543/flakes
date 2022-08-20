{
  self,
  inputs,
  ...
}: with inputs; {
  imports = [ (digga.lib.importExportableModules ../users/modules) ];
  importables =  with inputs; rec {
    profiles = digga.lib.rakeLeaves ../users/profiles;
    suites = with profiles; rec {
      base = [ direnv git zsh gpg neovim ssh tools ];
    };
  };
  users = {
    tippy = { suites, ... }: { imports = suites.base; };
  };
}
