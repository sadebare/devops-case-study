# Credentials come from the environment (AWS SSO profile, or an assumed role
# in automation). Nothing is configured here on purpose.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Service     = var.service_name
        Environment = var.environment
      },
      var.tags,
    )
  }
}
