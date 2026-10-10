# Extra permissions so the terraform workflow can manage the VPC and the EKS
# cluster in ../modules/vpc and ../modules/eks. Kept in managed policies, not
# the inline ones in github-actions.tf, because all inline policies on a role
# share a 10 KB limit.
#
# Scoping: EKS, IAM and CloudWatch Logs are limited to resources named after
# the service. EC2 networking actions mostly cannot be limited by resource
# when creating, so they are limited to this region instead.

locals {
  eks_cluster_name     = var.service_name
  eks_resource_prefix  = "arn:aws:eks:${var.aws_region}:${local.account_id}"
  eks_role_arn_pattern = "arn:aws:iam::${local.account_id}:role/${var.service_name}-eks-*"
  eks_log_group_arn    = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/eks/${local.eks_cluster_name}/*"

  eks_resource_arns = [
    "${local.eks_resource_prefix}:cluster/${local.eks_cluster_name}",
    "${local.eks_resource_prefix}:nodegroup/${local.eks_cluster_name}/*",
    "${local.eks_resource_prefix}:addon/${local.eks_cluster_name}/*",
    "${local.eks_resource_prefix}:access-entry/${local.eks_cluster_name}/*",
  ]

  # The only AWS managed policies the pipeline may attach to the EKS roles.
  eks_attachable_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ]
}

# ---- read: plan and apply ---------------------------------------------------

data "aws_iam_policy_document" "platform_read" {
  # Describe calls do not support resource-level permissions.
  statement {
    sid       = "Ec2Describe"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid    = "EksRead"
    effect = "Allow"
    actions = [
      "eks:Describe*",
      "eks:List*",
    ]
    resources = local.eks_resource_arns
  }

  statement {
    sid    = "EksCatalogRead"
    effect = "Allow"
    actions = [
      "eks:DescribeAddonVersions",
      "eks:DescribeAddonConfiguration",
      "eks:DescribeClusterVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EksRolesRead"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.eks_role_arn_pattern]
  }

  # EKS checks that its service-linked roles exist before creating a
  # cluster or node group, using the caller's permissions.
  statement {
    sid     = "ServiceLinkedRolesRead"
    effect  = "Allow"
    actions = ["iam:GetRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
      "arn:aws:iam::${local.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup",
      "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    ]
  }

  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "LogsRead"
    effect = "Allow"
    actions = [
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
    ]
    resources = [local.eks_log_group_arn]
  }
}

resource "aws_iam_policy" "platform_read" {
  name        = "${var.service_name}-terraform-platform-read"
  description = "Read the VPC and EKS resources managed by the ${var.service_name} terraform workflow."
  policy      = data.aws_iam_policy_document.platform_read.json
}

# ---- write: apply only ------------------------------------------------------

data "aws_iam_policy_document" "platform_write" {
  statement {
    sid    = "Ec2Network"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # Creating a node group from a launch template makes EKS check that the
  # caller could launch instances with it. Instances may only be launched
  # through a launch template, in this region.
  statement {
    sid       = "Ec2RunInstancesFromLaunchTemplate"
    effect    = "Allow"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*"]

    condition {
      test     = "ArnLike"
      variable = "ec2:LaunchTemplate"
      values   = ["arn:aws:ec2:${var.aws_region}:${local.account_id}:launch-template/*"]
    }
  }

  # The other resources a launch touches. They do not carry the launch
  # template condition key, so they need their own statement.
  statement {
    sid     = "Ec2RunInstancesResources"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:launch-template/*",
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:subnet/*",
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:network-interface/*",
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:security-group/*",
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}::image/*",
    ]
  }

  statement {
    sid       = "EksManage"
    effect    = "Allow"
    actions   = ["eks:*"]
    resources = local.eks_resource_arns
  }

  statement {
    sid    = "EksRolesManage"
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
    ]
    resources = [local.eks_role_arn_pattern]
  }

  # Attach only the three EKS policies, so a change cannot attach
  # AdministratorAccess to the node role.
  statement {
    sid       = "EksRolesAttach"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = [local.eks_role_arn_pattern]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.eks_attachable_policy_arns
    }
  }

  statement {
    sid       = "EksRolesPass"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.eks_role_arn_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      # EC2 for the node role, which the launch check above also verifies.
      values = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  # EKS and its node groups run through service-linked roles, created on
  # first use in an account. Nothing else may be created this way.
  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "autoscaling.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "LogsManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
    ]
    resources = [local.eks_log_group_arn]
  }
}

resource "aws_iam_policy" "platform_write" {
  name        = "${var.service_name}-terraform-platform-write"
  description = "Manage the VPC and EKS resources of the ${var.service_name} terraform workflow."
  policy      = data.aws_iam_policy_document.platform_write.json
}

resource "aws_iam_role_policy_attachment" "platform_read" {
  for_each = aws_iam_role.terraform

  role       = each.value.name
  policy_arn = aws_iam_policy.platform_read.arn
}

resource "aws_iam_role_policy_attachment" "platform_write" {
  role       = aws_iam_role.terraform["apply"].name
  policy_arn = aws_iam_policy.platform_write.arn
}
