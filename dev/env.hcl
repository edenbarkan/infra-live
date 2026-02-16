# Purpose: All variables that differ between dev and prod live here.
# Child modules read these via: read_terragrunt_config(find_in_parent_folders("env.hcl"))

locals {
  environment  = "dev"
  cluster_name = "myapp-dev"
  vpc_cidr     = "10.0.0.0/16"
  eks_version  = "1.30"
  namespaces   = ["dev", "staging"]

  # Karpenter: spot instances for dev = ~70% cost savings
  karpenter_instance_families = ["t3", "m5"]
  karpenter_capacity_types    = ["spot"]

  tags = { Environment = "dev" }
}