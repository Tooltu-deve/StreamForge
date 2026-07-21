# Reference the existing GitHub OIDC provider (created outside this stack)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# Trust policy: WHO may assume this role.
# Only GitHub Actions OIDC tokens from our specific repo can assume it.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be AWS STS
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to our repo (any branch/PR for now — tighten later)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "streamforge-github-actions-ci"
  description        = "Assumed by GitHub Actions (OIDC) to run Terraform CI"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# ---------------------------------------------------------------------------
# Permission policy: WHAT the role can do.
# Minimum for `terraform init` + `plan`: access to remote state + read APIs.
# Expand/tighten as later phases add resources.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ci_permissions" {
  # -- Terraform state (S3 backend) --
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid       = "StateObjectReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/*"]
  }

  # -- KMS key that encrypts the state --
  statement {
    sid       = "StateKmsAccess"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.state_kms_key_arn]
  }

  # -- Read-only APIs so `terraform plan` can refresh existing resources.
  #    Starting point; scope down (or split a plan vs apply role) later. --
  statement {
    sid    = "ReadOnlyForPlan"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "iam:Get*",
      "iam:List*",
      "s3:GetBucket*",
      "s3:ListAllMyBuckets",
      "route53:Get*",
      "route53:List*",
      "acm:Describe*",
      "acm:List*",
      "eks:Describe*", "eks:List*",
      "dynamodb:Describe*", "dynamodb:List*",
      "ecr:Describe*", "ecr:List*", "ecr:GetRepositoryPolicy",
      "cognito-idp:Describe*", "cognito-idp:List*", "cognito-idp:Get*",
      "kms:Describe*", "kms:List*",
      "logs:Describe*",
      "autoscaling:Describe*",

    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_permissions" {
  name   = "streamforge-ci-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}
