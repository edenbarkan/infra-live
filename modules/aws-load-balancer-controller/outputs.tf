output "iam_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.lb_controller_irsa.iam_role_arn
}