locals {
  oidc_host = replace(data.terraform_remote_state.core.outputs.oidc_provider_url, "https://", "")
  namespace = "streamforge"
  services  = ["catalog", "upload", "playback"]
}

data "aws_iam_policy_document" "svc_assume" {
  for_each = toset(local.services)
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.core.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${each.key}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "svc" {
  for_each           = toset(local.services)
  name_prefix        = "sf-${each.key}-"
  assume_role_policy = data.aws_iam_policy_document.svc_assume[each.key].json
}

data "aws_iam_policy_document" "upload" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${data.terraform_remote_state.core.outputs.raw_bucket_arn}/raw/*"]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [data.terraform_remote_state.core.outputs.table_arn]
  }
}


data "aws_iam_policy_document" "catalog" {
  statement {
    actions = ["dynamodb:Query", "dynamodb:GetItem"]
    resources = [
      data.terraform_remote_state.core.outputs.table_arn,
      "${data.terraform_remote_state.core.outputs.table_arn}/index/*"
    ]
  }
}

data "aws_iam_policy_document" "playback" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${data.terraform_remote_state.core.outputs.raw_bucket_arn}/raw/*"]
  }

  statement {
    actions   = ["dynamodb:GetItem"]
    resources = [data.terraform_remote_state.core.outputs.table_arn]
  }
}

resource "aws_iam_role_policy" "svc" {
  for_each = {
    upload   = data.aws_iam_policy_document.upload.json
    catalog  = data.aws_iam_policy_document.catalog.json
    playback = data.aws_iam_policy_document.playback.json
  }

  name_prefix = "sf-${each.key}-"
  role        = aws_iam_role.svc[each.key].id
  policy      = each.value
}