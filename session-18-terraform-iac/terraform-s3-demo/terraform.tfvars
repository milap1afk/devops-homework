aws_region                         = "ap-south-1"
bucket_prefix                      = "milap-devops-s3-demo"
enable_versioning                  = true
noncurrent_version_expiration_days = 30
offline_plan                       = true

tags = {
  Project   = "devops-homework"
  Session   = "18"
  ManagedBy = "terraform"
  Owner     = "milap"
}
