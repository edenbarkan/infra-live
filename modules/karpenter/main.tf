# --- KARPENTER IAM & INFRASTRUCTURE ---
# This sub-module creates:
# 1. IAM role for Karpenter controller (to launch EC2 instances)
# 2. IAM role for Karpenter-managed nodes (instance profile)
# 3. SQS queue + EventBridge rules for spot interruption handling
# 4. Pod Identity Association (modern AWS-recommended auth method)

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = var.cluster_name

  # EKS Pod Identity (modern AWS best practice, replaces IRSA)
  # Simpler than OIDC, AWS-managed, better performance
  enable_pod_identity             = true
  create_pod_identity_association = true

  # CRITICAL: Pod Identity must be in same namespace as Karpenter Helm release
  namespace = "karpenter"

  # Spot interruption handling: AWS sends 2-minute warning before terminating spot instance
  # Karpenter gracefully drains pods to other nodes
  enable_spot_termination = true

  tags = var.tags
}

# --- KARPENTER HELM CHART ---
# Installs the Karpenter controller into the cluster

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.0"
  wait             = true

  values = [yamlencode({
    settings = {
      clusterName       = var.cluster_name
      clusterEndpoint   = var.cluster_endpoint
      interruptionQueue = module.karpenter.queue_name  # SQS queue for spot interruptions
    }
    # Pod Identity: No annotations needed!
    # The Pod Identity Association automatically links the SA to IAM role
    serviceAccount = {
      name = "karpenter"  # Must match the Pod Identity Association
    }
  })]

  # Karpenter must run on system nodes (not Karpenter-managed nodes!)
  # Otherwise: chicken-and-egg problem
  depends_on = [module.karpenter]
}

# --- EC2NODECLASS: HOW TO LAUNCH NODES ---
# Tells Karpenter: which AMI, subnets, security groups to use

resource "kubectl_manifest" "node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      # Amazon Linux 2023 (latest, optimized for EKS)
      amiFamily = "AL2023"
      
      # IAM role for nodes (allows kubelet to join cluster, pull ECR images, etc.)
      role = module.karpenter.node_iam_role_name
      
      # Find subnets by tag (Karpenter looks for subnets with this tag)
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      
      # Find security groups by tag
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      
      # User data script (optional customizations)
      # userData can be added here if you need custom node setup
    }
  })
  
  depends_on = [helm_release.karpenter]
}

# --- NODEPOOL: WHAT KIND OF NODES TO LAUNCH ---
# Tells Karpenter: instance types, limits, consolidation rules

resource "kubectl_manifest" "node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          # Requirements: constraints for instance selection
          requirements = [
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.instance_families  # e.g., ["t3", "m5"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.capacity_types  # e.g., ["spot"] or ["on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]  # ARM (graviton) is cheaper but not all images support it
            }
          ]
          
          # Link to EC2NodeClass (tells Karpenter HOW to launch)
          nodeClassRef = { name = "default" }
        }
      }
      
      # Limits: prevent runaway scaling
      limits = {
        cpu = var.cpu_limit  # Max CPU across all Karpenter nodes
      }
      
      # Disruption: when/how Karpenter can remove nodes
      disruption = {
        # Consolidation: if nodes are underutilized, merge workloads onto fewer nodes
        consolidationPolicy = "WhenUnderutilized"
        
        # Recycle nodes every 30 days (gets latest AMI patches)
        expireAfter = "720h"
      }
    }
  })
  
  depends_on = [kubectl_manifest.node_class]
}
