# Purpose: Wires the EKS module to the dev environment.

include "root" {
  path = find_in_parent_folders()   # Inherits remote_state + provider
}

terraform {
  source = "../../modules/eks"       # Points to our module
}

dependency "vpc" {
  config_path = "../vpc"             # Waits for VPC to be created first

  mock_outputs = {
    vpc_id          = "mock-vpc-id"
    private_subnets = ["mock-subnet-1", "mock-subnet-2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "destroy", "plan"]
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name                = local.env.locals.cluster_name
  eks_version                 = local.env.locals.eks_version
  environment                 = local.env.locals.environment
  vpc_id                      = dependency.vpc.outputs.vpc_id
  private_subnet_ids          = dependency.vpc.outputs.private_subnets
  system_node_instance_types  = local.env.locals.system_node_instance_types
  system_node_min_size        = local.env.locals.system_node_min_size
  system_node_max_size        = local.env.locals.system_node_max_size
  system_node_desired_size    = local.env.locals.system_node_desired_size
  tags                        = local.env.locals.tags
}