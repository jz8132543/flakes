terraform {
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
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    b2 = {
      source = "Backblaze/b2"
    }
    assert = {
      source = "bwoznicki/assert"
    }
  }
}
