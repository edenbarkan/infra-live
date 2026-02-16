output "node_iam_role_arn" {
  description = "IAM role ARN that Karpenter-managed nodes use"
  value       = module.karpenter.node_iam_role_arn
}

output "node_iam_role_name" {
  description = "IAM role name that Karpenter-managed nodes use"
  value       = module.karpenter.node_iam_role_name
}

output "queue_name" {
  description = "SQS queue name for spot interruption handling"
  value       = module.karpenter.queue_name
}
