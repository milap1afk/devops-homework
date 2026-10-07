variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "devops-s19"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.20.1.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro" # free-tier eligible
}

variable "ami_id" {
  description = "AMI to use. Empty = look up the latest Ubuntu 24.04 LTS automatically."
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr" {
  description = "Who may SSH in. Use your own IP/32, never 0.0.0.0/0 in real life."
  type        = string
  default     = "203.0.113.10/32"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR, e.g. 203.0.113.10/32."
  }
}

variable "offline_plan" {
  type    = bool
  default = false
}
