include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/external-secrets"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                    = "https://mock-eks-endpoint"
    cluster_certificate_authority_data  = "bW9jay1jZXJ0LWRhdGE="
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

dependency "aws_load_balancer_controller" {
  config_path = "../aws-load-balancer-controller"

  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name                        = local.env.locals.cluster_name
  cluster_endpoint                    = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data  = dependency.eks.outputs.cluster_certificate_authority_data
  secret_prefixes                     = local.env.locals.namespaces
  region                              = "us-east-1"
  tags                                = local.env.locals.tags
}
