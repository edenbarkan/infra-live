variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "namespaces" {
  description = "List of namespaces ArgoCD can deploy to"
  type        = list(string)
}

variable "helm_charts_repo_url" {
  description = "Git repository URL containing Helm charts"
  type        = string
  default     = "https://github.com/your-org/helm-charts.git"
}

variable "domain" {
  description = "Domain for ArgoCD UI (e.g., argocd.dev.example.com)"
  type        = string
  default     = "localhost"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  type        = string
}
