# Purpose: Creates VPC with public/private subnets across 3 AZs.
# Public subnets  → ALB (internet-facing)
# Private subnets → EKS nodes + pods

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1), cidrsubnet(var.vpc_cidr, 4, 2)]
  private_subnets = [cidrsubnet(var.vpc_cidr, 4, 4), cidrsubnet(var.vpc_cidr, 4, 5), cidrsubnet(var.vpc_cidr, 4, 6)]

  # NAT Gateway: 1 for dev (cost saving), 1 per AZ for prod (HA)
  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "dev"
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  # These tags tell AWS LBC and Karpenter which subnets to use
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1                          # ALB uses these
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name  # Karpenter finds subnets by this tag
  }

  tags = var.tags
}