# ---------------------------------------------------------------------------
# GitHub Actions OIDC federation.
#
# Lets GitHub Actions assume an AWS IAM role using short-lived OIDC tokens
# instead of long-lived AWS access keys committed to repo secrets. This is
# the modern, security-best-practice way to give a CI/CD pipeline AWS
# permissions: a leaked GitHub Actions log can't be replayed because the
# credentials it briefly held expired within an hour.
# ---------------------------------------------------------------------------

# GitHub's well-known OIDC issuer. Single provider per AWS account is enough -
# all the per-repo isolation happens in the trust policy below.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    # Documented GitHub OIDC thumbprints. AWS no longer strictly validates
    # them (since 2023 the API auto-fetches the live cert), but Terraform's
    # schema still requires the field.
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name = "${local.name_prefix}-github-oidc"
  }
}

# Trust policy: only the expense-tracker-api repo, on the main branch or
# in a pull request, can assume this role. ANY other repo / branch / fork
# gets denied even though they go through the same OIDC provider.
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be sts.amazonaws.com - this is the default when the
    # workflow uses aws-actions/configure-aws-credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Repo + branch / event scoping. The `sub` claim from GitHub looks like:
    #   repo:KevinMM007/expense-tracker-api:ref:refs/heads/main
    #   repo:KevinMM007/expense-tracker-api:pull_request
    # Any other repo or branch fails the StringLike match.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:KevinMM007/expense-tracker-api:ref:refs/heads/main",
        "repo:KevinMM007/expense-tracker-api:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
  description        = "Assumed by GitHub Actions in KevinMM007/expense-tracker-api via OIDC. Builds and deploys the Lambda container."

  tags = {
    Name = "${local.name_prefix}-github-actions-deploy"
  }
}

# Permissions: just enough to push to ECR and update the Lambda. No VPC,
# no RDS, no Secrets Manager. The deploy pipeline does NOT need to read
# runtime data - that's the Lambda's role.
data "aws_iam_policy_document" "github_actions_deploy" {
  # ECR auth - needs to be *
  statement {
    sid       = "ECRAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR push / pull on the specific repo only
  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  # Lambda: update code + smoke-test invocation
  statement {
    sid = "LambdaUpdateAndInvoke"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:InvokeFunction",
    ]
    resources = [aws_lambda_function.api.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "${local.name_prefix}-github-actions-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
