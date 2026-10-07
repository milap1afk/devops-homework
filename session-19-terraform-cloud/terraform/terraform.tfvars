aws_region         = "ap-south-1"
project            = "devops-s19"
environment        = "dev"
vpc_cidr           = "10.20.0.0/16"
public_subnet_cidr = "10.20.1.0/24"
instance_type      = "t3.micro"
ssh_allowed_cidr   = "203.0.113.10/32" # replace with your own IP/32

# Offline homework mode: no AWS account. Remove these two lines to deploy for real
# (an empty ami_id auto-selects the latest Ubuntu 24.04).
offline_plan = true
ami_id       = "ami-0offlineplaceholder"
