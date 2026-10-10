variable "name" {
  description = "Name of the cluster. Also the prefix for its IAM roles (<name>-eks-cluster, <name>-eks-node)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane. Nodes follow it."
  type        = string
  default     = "1.37"
}

variable "subnet_ids" {
  description = "Private subnets, in at least two AZs, for the nodes and the control plane network interfaces."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Narrow this to your own IP (x.x.x.x/32) where possible."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "IAM users or roles given cluster admin through EKS access entries."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) > 0
    error_message = "At least one admin is needed, or nobody can use the cluster."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the nodes may pull from. Nothing else in ECR is readable."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "At least one ECR repository ARN is required."
  }
}

variable "addon_registry_account_id" {
  description = "AWS account that hosts the EKS add-on images for this region. 602401143452 covers eu-west-1 and most commercial regions."
  type        = string
  default     = "602401143452"
}

variable "node_instance_types" {
  description = "Instance types for the node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_count" {
  description = "Number of worker nodes. Two spreads the two app replicas across AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Root volume size of each node in GiB."
  type        = number
  default     = 20
}

variable "log_retention_days" {
  description = "Days to keep the control plane logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
