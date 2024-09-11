variable "terraform_input_path" {
  type = string
}

data "sops_file" "terraform" {
  source_file = var.terraform_input_path
}
#data "sops_file" "terraform" {
#  source_file = "../secrets/terraform-inputs.yaml"
#}
data "sops_file" "common" {
  source_file = "../secrets/common.yaml"
}
