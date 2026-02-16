variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint (Karpenter connects to this)"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name for Karpenter-managed nodes (optional, module creates if not provided)"
  type        = string
  default     = ""
}

variable "instance_families" {
  description = "List of EC2 instance families Karpenter can use (e.g., ['t3', 'm5'])"
  type        = list(string)
}

variable "capacity_types" {
  description = "Instance purchasing options (e.g., ['spot'] for dev, ['on-demand'] for prod)"
  type        = list(string)
}

variable "environment" {
  description = "Environment name (dev/prod) - affects CPU limits"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
