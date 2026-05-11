# ---------------------------------------------------------------------------
# Security groups: least-privilege traffic rules between Lambda and RDS.
#
# Pattern: reference SGs by ID rather than CIDR blocks. That way the rules
# stay valid no matter how the subnet layout changes, and only the specific
# Lambda function can talk to the DB — not "anything in the VPC".
# ---------------------------------------------------------------------------

# Lambda SG — egress only. Inbound is irrelevant: API Gateway invokes Lambda
# through the AWS control plane, not over the network.
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Security group for the Lambda function. Outbound to RDS and AWS APIs."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}

# RDS SG — accepts Postgres (5432) only from the Lambda SG. No CIDR ingress.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for the RDS Postgres instance. Inbound 5432 from Lambda SG only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  # Default-allow egress. The instance lives in a private subnet with no
  # internet route, so this is functionally closed — but declaring it
  # explicitly stops Terraform from drifting the default rule on each apply.
  egress {
    description = "All outbound (effectively closed by routing - no internet route in private subnets)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}
