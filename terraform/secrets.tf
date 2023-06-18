data "sops_file" "terraform" {
  source_file = "../secrets/terraform-inputs.yaml"
}
