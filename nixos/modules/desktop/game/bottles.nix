{ pkgs, ... }:
let
  bottles-orig = pkgs.bottles.override { removeWarningPopup = true; };
in
{
  environment.systemPackages = [
    bottles-orig
  ];

  environment.global-persistence.user.directories = [
    ".local/share/bottles"
    ".config/bottles"
    ".local/share/ms365"
    ".local/share/umu"
  ];
}
