terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend block: this configuration creates the bucket that every other
  # configuration uses as its backend, so it starts on local state. See the
  # README for moving this state into the bucket afterwards.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "terraform-state"
    }
  }
}
