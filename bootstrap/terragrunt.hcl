# Purpose: Bootstrap only. Uses LOCAL state (chicken-and-egg: can't use S3 before it exists).
# Run once: cd bootstrap && terragrunt apply
# After this, all other modules use the S3 backend.

locals {
  account_id = get_aws_account_id()
  region     = "us-east-1"
}

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
  region = "${local.region}"
}
EOF
}

inputs = {
  state_bucket_name = "tfstate-${local.account_id}-${local.region}"
  lock_table_name   = "terraform-locks-${local.account_id}"
}