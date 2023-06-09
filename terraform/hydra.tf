resource "hydra_project" "nixos" {
  name         = "nixos"
  display_name = "NixOS"
  description  = "NixOS, the purely functional Linux distribution"
  homepage     = "https://nixos.org/nixos"
  owner        = "terraform"
}

resource "hydra_jobset" "nixos_flakes" {
  project           = hydra_project.nixos.name
  state             = "enabled"
  name              = "flakes"
  type              = "flake"
  flake_uri         = "github:jz8132543/flakes"
  check_interval    = 120
  scheduling_shares = 100
  keep_evaluations  = 3
}
