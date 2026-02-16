locals {
  environment  = "prod"
  cluster_name = "myapp-prod"
  vpc_cidr     = "10.1.0.0/16"
  eks_version  = "1.30"
  namespaces   = ["production"]

  # Karpenter: on-demand only for production stability
  karpenter_instance_families = ["m5", "m6i", "c5"]
  karpenter_capacity_types    = ["on-demand"]

  tags = { Environment = "prod" }
}