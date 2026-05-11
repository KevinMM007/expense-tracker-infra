# Non-secret configuration values for this deployment.
# Safe to commit — contains no credentials.
# (If you add anything sensitive later, move it to *.auto.tfvars and gitignore it,
# or fetch it from AWS Secrets Manager / SSM Parameter Store at apply time.)

aws_region   = "us-east-2"
project_name = "expense-tracker"
environment  = "dev"
