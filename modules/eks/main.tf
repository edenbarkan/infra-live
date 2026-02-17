module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.eks_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.private_subnet_ids

  # --- CONTROL PLANE ACCESS ---
  # Enable both public and private access for deployment flexibility
  # Public access: Allows deployment from local machines/CI/CD (can restrict by IP if needed)
  # Private access: Allows nodes and pods to access API via VPC
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # --- MODERN AUTHENTICATION ---
  # Replaces the old aws-auth ConfigMap (which was error-prone)
  # Now you manage access via API instead of editing a ConfigMap
  authentication_mode = "API"

  # Grant yourself admin access to the cluster
  # You'll need to replace this with your actual IAM user/role ARN
  # To find it: aws sts get-caller-identity
  enable_cluster_creator_admin_permissions = true

  # --- EKS ADD-ONS (Managed by Terraform) ---
  # These are AWS-managed versions of core K8s components
  cluster_addons = {
    # CoreDNS: DNS resolution inside the cluster
    coredns = {
      most_recent = true
    }

    # kube-proxy: Network proxy on each node
    kube-proxy = {
      most_recent = true
    }

    # VPC-CNI: Gives pods real VPC IP addresses
    vpc-cni = {
      most_recent    = true
      before_compute = true  # Must be ready before nodes join

      # Enable prefix delegation: more IPs per node
      # Without this: max ~10-30 pods per node
      # With this: max ~110 pods per node
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          ENABLE_POD_ENI           = "true"
        }
      })
    }

    # EKS Pod Identity Agent: Required for Pod Identity to work
    # Runs as a DaemonSet on each node to enable IAM role assumption
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # --- CONTROL PLANE LOGGING ---
  # Send K8s API logs to CloudWatch for debugging
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # --- MANAGED NODE GROUP (System Nodes) ---
  # Small fixed-size node group for infrastructure pods
  # Application pods will run on Karpenter-managed nodes instead
  eks_managed_node_groups = {
    system = {
      instance_types = var.system_node_instance_types
      min_size       = var.system_node_min_size
      max_size       = var.system_node_max_size
      desired_size   = var.system_node_desired_size
      
      # Label these nodes for identification
      labels = {
        "node-role" = "system"
      }

      # No taints - allow all pods to schedule on these nodes
      # This enables infrastructure addons to deploy immediately after cluster creation
    }
  }

  # --- KARPENTER DISCOVERY TAGS ---
  # Karpenter looks for security groups with this tag
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# --- METRICS SERVER ---
# Metrics server is now installed via a separate module/addon
# This avoids Helm provider configuration issues during EKS creation
