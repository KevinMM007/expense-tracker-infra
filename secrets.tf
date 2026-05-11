# ---------------------------------------------------------------------------
# RDS master credentials, generated locally and stored in AWS Secrets Manager.
#
# Why Secrets Manager (not env vars / Parameter Store):
#   - Industry-standard service recruiters expect to see on a CV.
#   - Lambda fetches credentials at runtime via IAM, so the password never
#     ends up in Terraform state output, Lambda env vars, or GitHub Actions
#     logs.
#   - Cost: ~$0.40 / secret / month - trivial for a portfolio.
# ---------------------------------------------------------------------------

# Random 32-char password. `special = true` enables symbols; we override the
# allowed set to exclude characters that confuse Postgres connection strings
# or shell quoting ('"@/\). The remaining set is still high-entropy.
resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "${local.name_prefix}-rds-credentials"
  description = "Master credentials and connection info for the ${local.name_prefix} RDS Postgres instance."

  # 0 = delete immediately on destroy. AWS's default is 7-30 days, which
  # would make `terraform apply` fail after a recent destroy because the
  # secret name is still reserved. Portfolio convenience, not prod policy.
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name_prefix}-rds-credentials"
  }
}

# Store the full connection bundle as JSON. The Lambda code reads this single
# secret and pulls every field it needs - no scattered env vars to keep in sync.
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id

  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.rds_master.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}
