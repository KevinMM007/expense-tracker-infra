# ---------------------------------------------------------------------------
# IAM role assumed by the Lambda function at runtime.
#
# Combines two AWS-managed policies for the standard Lambda+VPC plumbing
# with a tight inline policy that grants read access to exactly one
# Secrets Manager secret. Least-privilege: even with this role, the Lambda
# cannot read any other secret in the account.
# ---------------------------------------------------------------------------

# Trust policy: only the Lambda service can assume this role.
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${local.name_prefix}-lambda-role"
  }
}

# Write to CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create / delete the ENIs Lambda uses when running inside a VPC.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Read the single RDS credentials secret. Inline policy keeps the
# permission scope visible right next to the resource it protects.
data "aws_iam_policy_document" "lambda_secrets_read" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.rds_credentials.arn]
  }
}

resource "aws_iam_role_policy" "lambda_secrets_read" {
  name   = "${local.name_prefix}-lambda-secrets-read"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secrets_read.json
}
