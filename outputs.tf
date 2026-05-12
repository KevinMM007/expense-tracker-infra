# Outputs surface key attributes after `terraform apply` so you can inspect
# the deployment without digging through the AWS console.

# ---------- Networking ----------

output "vpc_id" {
  description = "ID of the VPC that hosts all infrastructure."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (one per AZ). Empty by design; reserved for future bastion / ALB."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (one per AZ). Host RDS and Lambda."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "Availability zones used for the subnets."
  value       = slice(data.aws_availability_zones.available.names, 0, local.az_count)
}

# ---------- Security groups ----------

output "lambda_security_group_id" {
  description = "Security group attached to the Lambda function."
  value       = aws_security_group.lambda.id
}

output "rds_security_group_id" {
  description = "Security group attached to the RDS instance. Accepts 5432 only from the Lambda SG."
  value       = aws_security_group.rds.id
}

# ---------- Database ----------

output "rds_endpoint" {
  description = "Connection endpoint for the RDS Postgres instance (host:port)."
  value       = aws_db_instance.main.endpoint
}

output "rds_db_name" {
  description = "Default database created on the RDS instance."
  value       = aws_db_instance.main.db_name
}

output "rds_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master credentials. Lambda reads from this at runtime."
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "rds_credentials_secret_name" {
  description = "Name of the Secrets Manager secret (handy for `aws secretsmanager get-secret-value` from the CLI)."
  value       = aws_secretsmanager_secret.rds_credentials.name
}

# ---------- Container registry ----------

output "ecr_repository_url" {
  description = "URL of the ECR repository that hosts the Lambda container image. Used as the target for `docker push`."
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_repository_name" {
  description = "Short name of the ECR repository (useful for AWS CLI commands)."
  value       = aws_ecr_repository.api.name
}

# ---------- Compute ----------

output "lambda_function_name" {
  description = "Name of the Lambda function. Use with `aws lambda update-function-code` etc."
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function."
  value       = aws_lambda_function.api.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group capturing Lambda invocations. Tail with `aws logs tail`."
  value       = aws_cloudwatch_log_group.lambda.name
}

# ---------- Public endpoint ----------

output "api_gateway_invoke_url" {
  description = "Public HTTPS URL serving the API. This is what curl / browsers / recruiters hit."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

# ---------- CI / CD ----------

output "github_actions_role_arn" {
  description = "IAM role ARN that GitHub Actions assumes via OIDC. Paste into the workflow's role-to-assume."
  value       = aws_iam_role.github_actions.arn
}
