data "sops_file" "terraform" {
  source_file = "../secrets/terraform-inputs.yaml"
}

provider "hydra" {
  host     = "https://hydra.dora.im"
  username = "terraform"
  password = data.sops_file.terraform.data["hydra.password"]
}
