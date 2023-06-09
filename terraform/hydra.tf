resource "hydra_project" "misc" {
  name         = "misc"
  display_name = "Misc"
  description  = "Miscellaneous projects"
  owner        = "terraform"
}

resource "hydra_jobset" "misc_flakes" {
  project           = hydra_project.misc.name
  state             = "enabled"
  name              = "flakes"
  type              = "flake"
  flake_uri         = "github:jz8132543/flakes"
  check_interval    = 120
  scheduling_shares = 100
  keep_evaluations  = 2
}
