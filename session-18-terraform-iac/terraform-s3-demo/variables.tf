variable "aws_region" {
  description = "AWS region to create the bucket in"
  type        = string
  default     = "ap-south-1"
}

variable "bucket_prefix" {
  description = "Prefix for the bucket name (a random suffix keeps it globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,40}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 3-41 chars: lowercase letters, numbers and hyphens."
  }
}

variable "enable_versioning" {
  description = "Keep old versions of every object"
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Delete old object versions after this many days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}

variable "offline_plan" {
  description = "true = plan without real AWS credentials (homework / CI validation)"
  type        = bool
  default     = false
}
