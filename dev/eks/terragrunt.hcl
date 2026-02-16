# Purpose: Wires the EKS module to the dev environment.

include "root" {
  path = find_in_parent_folders()   # Inherits remote_state + provider
}

terraform {
  source = "../../modules/eks"       # Points to our module
}

dependency "vpc" {
  config_path = "../vpc"             # Waits for VPC to be created first
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name       = local.env.locals.cluster_name
  eks_version        = local.env.locals.eks_version
  environment        = local.env.locals.environment
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets
  tags               = local.env.locals.tags
}