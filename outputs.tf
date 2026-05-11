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

# ---------- Planned outputs (added as resources land) ----------
# - rds_endpoint
# - lambda_function_name
# - api_gateway_invoke_url   # the live HTTPS URL recruiters will hit
