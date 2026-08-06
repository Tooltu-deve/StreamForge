locals {
  oidc_host = replace(data.terraform_remote_state.core.outputs.oidc_provider_url, "https://", "")
  namespace = "streamforge"
  services  = ["catalog", "upload", "playback", "transcode-worker"]
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

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.terraform_remote_state.core.outputs.cf_signing_secret_arn]
  }
}

resource "aws_iam_role_policy" "svc" {
  for_each = {
    upload           = data.aws_iam_policy_document.upload.json
    catalog          = data.aws_iam_policy_document.catalog.json
    playback         = data.aws_iam_policy_document.playback.json
    transcode-worker = data.aws_iam_policy_document.transcode-worker.json
  }

  name_prefix = "sf-${each.key}-"
  role        = aws_iam_role.svc[each.key].id
  policy      = each.value
}

data "aws_iam_policy_document" "transcode-worker" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${data.terraform_remote_state.core.outputs.raw_bucket_arn}/raw/*"]
  }

  statement {
    actions = ["s3:PutObject"]
    resources = [
      "${data.terraform_remote_state.core.outputs.transcoded_bucket_arn}/hls/*",
      "${data.terraform_remote_state.core.outputs.transcoded_bucket_arn}/thumbs/*"
    ]
  }

  statement {
    actions   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
    resources = [data.terraform_remote_state.core.outputs.table_arn]
  }

  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [data.terraform_remote_state.core.outputs.queue_arn]
  }
}