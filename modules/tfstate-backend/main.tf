# Purpose: Creates the S3 bucket and DynamoDB table that Terragrunt uses
#          for remote state storage and state locking.
#
# Why DynamoDB lock?
#   Without it, two people running "terragrunt apply" at the same time
#   can corrupt the state file. DynamoDB provides a distributed lock —
#   only one apply can run per module at a time.
#
# This module is a one-time bootstrap — run it BEFORE everything else.

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State"
    ManagedBy = "terraform"
  }
}

# Enable versioning so we can recover from bad state
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest (contains sensitive outputs like endpoints, ARNs)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to the state bucket
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
# Terragrunt automatically acquires a lock before apply and releases after.
# If someone else is already applying, you'll see: "Error locking state"
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # No capacity planning needed
  hash_key     = "LockID"          # Required by Terraform — don't change

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform Lock Table"
    ManagedBy = "terraform"
  }
}