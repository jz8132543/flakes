{ self, inputs, ... }@args:
with inputs; {
  hostDefaults = import ./hostDefault.nix args;

  imports = [ (digga.lib.importHosts ../hosts) ];

  hosts = import ./hosts.nix args;

  importables = import ./suites.nix args;
}
