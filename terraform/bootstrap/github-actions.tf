# Lets the terraform workflow (.github/workflows/terraform.yml) plan and apply
# the main configuration in ../ through GitHub OIDC, with no stored keys.
#
# These roles live here and not in ../ on purpose: the pipeline applies ../,
# so if its own roles were defined there, a merged change could widen the
# pipeline's permissions. This folder is only ever applied by an engineer.

data "aws_caller_identity" "current" {}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  account_id       = data.aws_caller_identity.current.account_id

  # Everything the main configuration manages, so the roles can be scoped to it.
  state_object_prefix = "${module.state_bucket.bucket_arn}/${var.service_name}/"
  state_lock_object   = "${module.state_bucket.bucket_arn}/${var.service_name}/terraform.tfstate.tflock"
  ecr_repository_arn  = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.service_name}"
  ci_role_arn         = "arn:aws:iam::${local.account_id}:role/${var.service_name}-github-actions"

  # Who may assume each role, as the "sub" claim of the GitHub OIDC token.
  # Pull request runs get the read-only plan role. Only jobs running in the
  # protected environment get the apply role, so a pull request cannot apply
  # even if someone edits the workflow in their branch.
  subject_prefix = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repository}")
  terraform_role_subjects = {
    plan  = "${local.subject_prefix}:pull_request"
    apply = "${local.subject_prefix}:environment:${var.apply_environment}"
  }
}

# One per AWS account. The main configuration looks it up instead of creating
# it (create_github_oidc_provider = false). No thumbprint_list: AWS validates
# GitHub's certificate against its own trusted root CAs.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "terraform_trust" {
  for_each = local.terraform_role_subjects

  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "terraform" {
  for_each = local.terraform_role_subjects

  name                 = "${var.service_name}-terraform-${each.key}"
  description          = "Assumed by GitHub Actions in ${var.github_repository} to run terraform ${each.key}."
  assume_role_policy   = data.aws_iam_policy_document.terraform_trust[each.key].json
  max_session_duration = 3600
}

# What `terraform plan` needs: read the state, take the state lock, and read
# the resources the main configuration manages. Nothing can be changed.
data "aws_iam_policy_document" "terraform_read" {
  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.state_bucket.bucket_arn]
  }

  statement {
    sid       = "StateRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_object_prefix}*"]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_lock_object]
  }

  statement {
    sid    = "EcrRead"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
    ]
    resources = [local.ecr_repository_arn]
  }

  statement {
    sid    = "CiRoleRead"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [local.ci_role_arn]
  }

  # The main configuration looks the provider up by URL, which lists them all.
  # ListOpenIDConnectProviders does not support resource-level permissions.
  statement {
    sid       = "OidcProviderList"
    effect    = "Allow"
    actions   = ["iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  statement {
    sid       = "OidcProviderRead"
    effect    = "Allow"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }
}

# What `terraform apply` needs on top of that: write the state, and manage the
# ECR repository and the image-push role. Nothing outside those two resources.
data "aws_iam_policy_document" "terraform_write" {
  source_policy_documents = [data.aws_iam_policy_document.terraform_read.json]

  statement {
    sid       = "StateWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_object_prefix}*"]
  }

  statement {
    sid    = "EcrManage"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = [local.ecr_repository_arn]
  }

  statement {
    sid    = "CiRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.ci_role_arn]
  }
}

resource "aws_iam_role_policy" "terraform" {
  for_each = local.terraform_role_subjects

  name = "terraform-${each.key}"
  role = aws_iam_role.terraform[each.key].id
  policy = (
    each.key == "apply"
    ? data.aws_iam_policy_document.terraform_write.json
    : data.aws_iam_policy_document.terraform_read.json
  )
}
