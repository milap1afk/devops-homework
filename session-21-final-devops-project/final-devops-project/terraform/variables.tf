variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "cluster_name" {
  type    = string
  default = "kirana-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "azs" {
  description = "Two AZs for high availability"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_scaling" {
  type    = object({ min = number, desired = number, max = number })
  default = { min = 2, desired = 2, max = 4 }
}

variable "offline_plan" {
  type    = bool
  default = false
}
