terraform {
  backend "local" {
    path = "./terraform.tfstate"
  }
  required_providers {
    sops = {
      source = "carlpett/sops"
    }
    hydra = {
      source = "DeterminateSystems/hydra"
    }
  }
}
