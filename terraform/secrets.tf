data "sops_file" "terraform" {
  source_file = "../secrets/terraform-inputs.yaml"
}

locals {
  secrets = yamldecode(data.sops_file.terraform.raw)
}

provider "hydra" {
  host     = "https://hydra.dora.im"
  username = "terraform"
  password = local.secrets.hydra.password
}
