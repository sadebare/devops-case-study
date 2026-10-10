locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

# GitHub Actions presents a short-lived OIDC token; AWS trusts it through this
# provider. There are no access keys to store, rotate or leak.
# No thumbprint_list: AWS validates GitHub's certificate against its own
# trusted root CAs, and the argument is optional in current AWS providers.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

# Trust policy: WHO may assume the role. Exact matches only: this repository,
# these refs, this audience. Without the "sub" condition any repository on
# GitHub could assume the role.
data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = [for ref in var.allowed_refs : "repo:${var.github_repository}:ref:${ref}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Assumed by GitHub Actions in ${var.github_repository} to push images to ECR."
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration
  tags                 = var.tags
}

# Permissions policy: WHAT the role may do. Push (and the reads a push needs)
# on the named repositories, nothing else. No delete, no repository or policy
# management, no access to other repositories.
data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken does not support resource-level permissions; "*" is
  # the only value AWS accepts. The token it returns grants nothing by itself.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # Read access so a push can skip layers that already exist.
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
