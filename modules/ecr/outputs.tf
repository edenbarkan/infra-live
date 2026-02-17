output "repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.app.arn
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.app.name
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = try(aws_iam_role.github_actions[0].arn, "")
}
