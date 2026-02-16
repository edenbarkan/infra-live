include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/karpenter"
}

# Karpenter DEPENDS on EKS (needs cluster endpoint for Pod Identity)
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                    = "https://mock-eks-endpoint"
    cluster_certificate_authority_data  = "bW9jay1jZXJ0LWRhdGE="
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

# Karpenter needs AWS Load Balancer Controller webhook to be ready
# Without this dependency, Karpenter deployment fails with webhook timeout
dependency "aws_lbc" {
  config_path = "../aws-load-balancer-controller"
  skip_outputs = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name                        = local.env.locals.cluster_name
  cluster_endpoint                    = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data  = dependency.eks.outputs.cluster_certificate_authority_data
  instance_families                   = local.env.locals.karpenter_instance_families
  capacity_types                      = local.env.locals.karpenter_capacity_types
  environment                         = local.env.locals.environment
  tags                                = local.env.locals.tags
}