resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Enable image encryption
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# --- LIFECYCLE POLICY: Auto-cleanup old images ---

resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged after ${var.lifecycle_policy.untagged_days_to_keep} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_policy.untagged_days_to_keep
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.lifecycle_policy.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_policy.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
