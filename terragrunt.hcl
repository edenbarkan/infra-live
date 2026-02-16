# Purpose: Configures S3 backend for state + AWS provider for ALL child modules.
# Every child terragrunt.hcl inherits this automatically.

locals {
  # Try to read env.hcl, but don't fail if it doesn't exist (e.g., for ECR and bootstrap modules)
  # Using try() to safely handle missing env.hcl files
  env = try(read_terragrunt_config(find_in_parent_folders("env.hcl")), null)
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "tfstate-471448382412-us-east-1"
    key            = "${path_relative_to_include()}/terraform.tfstate"  # Auto-unique per module
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks-471448382412"     # Prevents concurrent applies
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "home-assignment"
      ManagedBy = "terragrunt"
    }
  }
}
EOF
}