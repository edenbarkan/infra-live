variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "lifecycle_policy" {
  description = "Lifecycle policy rules"
  type = object({
    max_image_count       = number
    untagged_days_to_keep = number
  })
  default = {
    max_image_count       = 20
    untagged_days_to_keep = 7
  }
}

variable "github_actions_role_enabled" {
  description = "Create IAM role for GitHub Actions OIDC"
  type        = bool
  default     = false
}

variable "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "GitHubActionsECRAccess"
}

variable "github_org" {
  description = "GitHub organization or user for OIDC trust"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
