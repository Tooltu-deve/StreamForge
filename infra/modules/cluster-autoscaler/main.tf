locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
  sa_name   = "cluster-autoscaler"
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:${local.sa_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name_prefix}-ca-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Read everything; mutate only ASGs tagged for this cluster.
data "aws_iam_policy_document" "ca" {
  statement {
    sid    = "Discover"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeImages",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "Mutate"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_role_policy" "ca" {
  name_prefix = "${var.name_prefix}-ca-"
  role        = aws_iam_role.this.id
  policy      = data.aws_iam_policy_document.ca.json
}

resource "helm_release" "this" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = "kube-system"

  set = [
    { name = "autoDiscovery.clusterName", value = var.cluster_name },
    { name = "awsRegion", value = var.region },
    { name = "rbac.serviceAccount.name", value = local.sa_name },
    { name = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = aws_iam_role.this.arn },
    { name = "extraArgs.balance-similar-node-groups", value = "true" },
    { name = "extraArgs.expander", value = "least-waste" },
  ]
}
