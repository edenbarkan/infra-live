include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/ingress"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                    = "https://mock-eks-endpoint"
    cluster_certificate_authority_data  = "bW9jay1jZXJ0LWRhdGE="
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

# Must deploy AFTER AWS Load Balancer Controller
dependency "aws_lbc" {
  config_path = "../aws-load-balancer-controller"

  mock_outputs = {
    mock_value = "mock"
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
  environment                         = local.env.locals.environment
  replica_count                       = local.env.locals.nginx_replica_count
  tags                                = local.env.locals.tags
}
