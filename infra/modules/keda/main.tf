locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
  sa_name   = "keda-operator"
  namespace = "keda"
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
      values   = ["system:serviceaccount:${local.namespace}:${local.sa_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name_prefix}-keda-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "keda" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes"
    ]
    resources = [var.queue_arn]
  }
}

resource "aws_iam_role_policy" "keda" {
  name_prefix = "${var.name_prefix}-keda-"
  role        = aws_iam_role.this.id
  policy      = data.aws_iam_policy_document.keda.json
}

resource "helm_release" "this" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.chart_version
  namespace        = local.namespace
  create_namespace = true

  set = [
    { name = "serviceAccount.name", value = local.sa_name },
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = aws_iam_role.this.arn },
  ]
}

