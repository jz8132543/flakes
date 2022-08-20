{
  self,
  inputs,
  ...
}:
with inputs; rec {
  profiles = digga.lib.rakeLeaves ../profiles // {
      users = digga.lib.rakeLeaves ../users;
    };
  suites = nixos.lib.fix (suites: {
    core = suites.nixSettings ++ (with profiles; [ programs.tools services.openssh ]);
    nixSettings = with profiles.nix; [ gc settings cachix ];
    base = suites.core ++
    (with profiles; [
      users.root
      users.tippy
    ]);
    network = with profiles; [
      networking.common
      networking.resolved
      networking.tools
    ];
    server = (with suites; [
      base
      network
    ]);
  });
}
