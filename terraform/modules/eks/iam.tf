data "aws_region" "current" {}

# ---- control plane ----------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  description        = "Used by the EKS control plane of ${var.name}."
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---- worker nodes -----------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  description        = "Used by the worker nodes of ${var.name}."
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

# Join the cluster, and let the VPC CNI hand out pod IPs. The CNI policy would
# move to a Pod Identity role once the cluster runs more than this one app.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Image pulls. This replaces the usual AmazonEC2ContainerRegistryReadOnly,
# which can read every repository in the account. Nodes can pull from:
#   - our own repositories (ecr_repository_arns), and
#   - the AWS account that hosts the EKS add-on images (VPC CNI, kube-proxy,
#     CoreDNS), without which the nodes never become Ready.
# Read only: no push, no delete, nothing else in ECR.
data "aws_iam_policy_document" "node_ecr_pull" {
  # GetAuthorizationToken does not support resource-level permissions; "*" is
  # the only value AWS accepts. The token it returns grants nothing by itself.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = concat(
      var.ecr_repository_arns,
      ["arn:aws:ecr:${data.aws_region.current.region}:${var.addon_registry_account_id}:repository/*"],
    )
  }
}

resource "aws_iam_role_policy" "node_ecr_pull" {
  name   = "ecr-pull"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node_ecr_pull.json
}
