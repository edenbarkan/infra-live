# Purpose: All variables that differ between dev and prod live here.
# Child modules read these via: read_terragrunt_config(find_in_parent_folders("env.hcl"))

locals {
  environment  = "dev"
  cluster_name = "myapp-dev"
  vpc_cidr     = "10.0.0.0/16"
  eks_version  = "1.35"
  namespaces   = ["dev", "staging"]

  # VPC
  single_nat_gateway = true  # Cost saving (use false for HA with 1 NAT per AZ)

  # EKS system nodes
  system_node_instance_types = ["t3.medium"]
  system_node_min_size       = 2
  system_node_max_size       = 2
  system_node_desired_size   = 2

  # Karpenter: spot instances for dev = ~70% cost savings
  karpenter_instance_families = ["t3", "m5"]
  karpenter_capacity_types    = ["spot"]
  karpenter_cpu_limit         = "20"

  # Ingress
  nginx_replica_count = 1  # Single replica sufficient for dev

  tags = { Environment = "dev" }
}