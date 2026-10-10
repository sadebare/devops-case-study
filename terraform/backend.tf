# Remote state in S3. The bucket is created by ./bootstrap.
#
# Partial configuration: the bucket name and region are account-specific, so
# they are supplied at init time instead of being committed:
#
#   cp backend.hcl.example backend.hcl   # then edit
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key     = "items-api/terraform.tfstate"
    encrypt = true

    # Lock with a conditional write of a .tflock object in the same bucket.
    # This replaces the DynamoDB lock table, which is deprecated.
    use_lockfile = true
  }
}
