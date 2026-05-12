# ---------------------------------------------------------------------------
# Lambda function (container image) and supporting bits.
# ---------------------------------------------------------------------------

# JWT signing secret. Stored as a Lambda env var rather than in Secrets
# Manager - rotating only needs an env var update, not a DB rotation.
# `special = false` keeps the secret URL-safe and shell-safe.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# Pre-create the log group so we control retention. Lambda would otherwise
# create it implicitly on first invocation with infinite retention - cheap
# to forget about, eventually pricey.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-api-logs"
  }
}

resource "aws_lambda_function" "api" {
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.lambda.arn

  # Container image deployment. Terraform tracks the URI, not the image
  # content - that's managed by `docker push` (and CI/CD later).
  package_type = "Image"
  image_uri    = "${aws_ecr_repository.api.repository_url}:latest"

  # 512 MB is comfortable for FastAPI + Mangum + alembic migrations on
  # cold start. Lambda scales CPU linearly with memory, so this also
  # cuts cold-start time vs the 128 MB minimum.
  memory_size = 512

  # Cold start budget:
  #   ~3-5 s   Lambda container init + image pull
  #   ~5-10 s  FastAPI module import + Mangum setup
  #   ~10-20 s alembic upgrade head (first run creates 3 tables)
  #   total    ~25-40 s on the very first invocation
  # Warm invocations are <1 s. We set 60 s so the first cold start
  # doesn't get cut off; API Gateway has its own 30 s hard limit so the
  # first-ever HTTP request from a real client may still hit 503 - that's
  # why we pre-warm via `aws lambda invoke` after every redeploy.
  timeout = 60

  # Must match the build arch (--platform linux/amd64 on the docker build).
  architectures = ["x86_64"]

  # Run inside the VPC so the function can reach RDS in private subnets.
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      # ----------------------------------------------------------------------
      # DB credentials trade-off:
      #
      # The "production-correct" pattern is to keep credentials in AWS Secrets
      # Manager and have the Lambda fetch them at cold start over IAM. That
      # requires either a NAT Gateway (~$35/month) or a Secrets Manager VPC
      # endpoint (~$7/month) so the Lambda in private subnets can reach the
      # Secrets Manager API.
      #
      # For this portfolio project we deliberately stay inside the AWS Free
      # Tier, so we pass DATABASE_URL directly as a Lambda env var. The
      # Secrets Manager resource is still created (and the Lambda still has
      # IAM read access to it) so the path is one VPC-endpoint commit away
      # from being "real" production: see README for the upgrade plan.
      #
      # The password is URL-encoded so symbols like '+' '=' '#' survive the
      # connection-string parser inside psycopg.
      # ----------------------------------------------------------------------
      DATABASE_URL = "postgresql+psycopg://${aws_db_instance.main.username}:${urlencode(random_password.rds_master.result)}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"

      JWT_SECRET_KEY = random_password.jwt_secret.result
      APP_ENV        = var.environment
      CORS_ORIGINS   = "*"

      # AWS_REGION is auto-injected by the Lambda runtime; not setting it here.
    }
  }

  # Make sure log group + IAM attachments exist before the function so logs
  # are captured from the very first invocation and the role has the right
  # permissions when Lambda assumes it.
  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_secrets_read,
  ]

  tags = {
    Name = "${local.name_prefix}-api"
  }
}
