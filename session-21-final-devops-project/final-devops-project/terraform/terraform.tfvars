region              = "ap-south-1"
environment         = "prod"
cluster_name        = "kirana-eks"
kubernetes_version  = "1.34"
node_instance_types = ["t3.medium"]
node_scaling        = { min = 2, desired = 2, max = 4 }

# offline homework mode: plan without an AWS account (remove to deploy for real)
offline_plan = true
