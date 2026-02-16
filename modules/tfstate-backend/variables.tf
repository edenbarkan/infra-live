variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "myproject-tfstate"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-locks"
}