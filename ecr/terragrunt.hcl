# ECR is SHARED across dev and prod (not per-environment)

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../modules/ecr"
}

inputs = {
  repository_name      = "myapp"
  image_tag_mutability = "MUTABLE"    # Branch tags (develop, main) are updated on each CI push
  scan_on_push         = true         # Scan for CVEs automatically
  
  lifecycle_policy = {
    max_image_count       = 20  # Keep last 20 images
    untagged_days_to_keep = 7   # Delete untagged after 7 days
  }

  tags = {
    Project   = "home-assignment"
    ManagedBy = "terragrunt"
  }
}
