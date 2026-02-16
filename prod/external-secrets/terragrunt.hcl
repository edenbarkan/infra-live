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
    oidc_provider_arn                   = "arn:aws:iam::123456789012:oidc-provider/mock"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name                        = local.env.locals.cluster_name
  cluster_endpoint                    = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data  = dependency.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn                   = dependency.eks.outputs.oidc_provider_arn
  environment                         = local.env.locals.environment
  region                              = "us-east-1"
  tags                                = local.env.locals.tags
}
