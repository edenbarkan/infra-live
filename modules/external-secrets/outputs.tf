output "iam_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = aws_iam_role.eso.arn
}

output "namespace" {
  description = "Namespace where External Secrets is deployed"
  value       = "external-secrets"
}
