output "iam_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = module.eso_irsa.iam_role_arn
}

output "namespace" {
  description = "Namespace where External Secrets is deployed"
  value       = "external-secrets"
}
