# Inherit remote state and provider from root
include "root" {
  path = find_in_parent_folders()
}

# Point to the VPC module
terraform {
  source = "../../modules/vpc"
}

# Read prod-specific variables
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# Pass values from env.hcl to the module
inputs = {
  cluster_name       = local.env.locals.cluster_name       # "myapp-prod"
  vpc_cidr           = local.env.locals.vpc_cidr           # "10.1.0.0/16"
  environment        = local.env.locals.environment        # "prod"
  single_nat_gateway = local.env.locals.single_nat_gateway # true
  tags               = local.env.locals.tags               # { Environment = "prod" }
}