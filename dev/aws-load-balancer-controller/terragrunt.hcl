include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/aws-load-balancer-controller"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-mock123"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                    = "https://mock-eks-endpoint"
    cluster_certificate_authority_data  = "bW9jay1jZXJ0LWRhdGE="
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
  vpc_id                              = dependency.vpc.outputs.vpc_id
  tags                                = local.env.locals.tags
}
