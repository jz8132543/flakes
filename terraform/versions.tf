terraform {
  # backend "http" {
  #   address = "http://127.0.0.1:5000"
  # }
  backend "local" {
    path = "terraform.tfstate"
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
