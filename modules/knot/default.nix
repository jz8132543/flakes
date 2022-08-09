{ ... }:

{
  services.knot = {
    enable = true;
    extraConfig = builtins.readFile ./knot.conf
  };
}
