# Fallback terragrunt config for modules that don't need environment-specific config
# (like ECR and bootstrap which are shared across environments)

locals {
  # Empty environment config
  environment  = "shared"
  cluster_name = ""
  vpc_cidr     = ""
  eks_version  = ""
  namespaces   = []
  karpenter_instance_families = []
  karpenter_capacity_types    = []
  tags = {}
}
