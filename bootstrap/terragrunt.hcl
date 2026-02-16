# Purpose: Bootstrap only. Uses LOCAL state (chicken-and-egg: can't use S3 before it exists).
# Run once: cd bootstrap && terragrunt apply
# After this, all other modules use the S3 backend.

terraform {
  source = "../modules/tfstate-backend"
}

# Local backend — this is the only module that doesn't use S3
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
}
EOF
}

inputs = {
  state_bucket_name = "tfstate-471448382412-us-east-1"
  lock_table_name   = "terraform-locks-471448382412"
}