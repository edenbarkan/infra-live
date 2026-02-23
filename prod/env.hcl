locals {
  environment  = "prod"
  cluster_name = "myapp-prod"
  vpc_cidr     = "10.1.0.0/16"
  eks_version  = "1.35"
  namespaces   = ["production"]

  # VPC
  single_nat_gateway = true  # Cost saving (use false for HA with 1 NAT per AZ)

  # EKS system nodes
  system_node_instance_types = ["t3.medium"]
  system_node_min_size       = 2
  system_node_max_size       = 2
  system_node_desired_size   = 2

  # Karpenter: spot + on-demand fallback for cost optimization
  karpenter_instance_families = ["m5", "m6i", "c5"]
  karpenter_capacity_types    = ["spot", "on-demand"]
  karpenter_cpu_limit         = "20"

  # Ingress
  nginx_replica_count = 2  # HA: one per system node

  tags = { Environment = "prod" }
}