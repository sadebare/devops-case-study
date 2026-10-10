variable "name" {
  description = "Name used for the VPC and as a prefix for its resources."
  type        = string
}

variable "cidr" {
  description = "CIDR block of the VPC. Must be a /16 so it splits into /20 subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && endswith(var.cidr, "/16")
    error_message = "cidr must be a valid /16 block, e.g. 10.0.0.0/16."
  }
}

variable "az_count" {
  description = "Number of availability zones. EKS needs subnets in at least two."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
