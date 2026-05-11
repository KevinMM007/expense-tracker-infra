# ---------------------------------------------------------------------------
# Amazon RDS for PostgreSQL 16, free-tier eligible.
#
# Cost-conscious choices:
#   - db.t3.micro: 750 hours/month free for 12 months (= 24/7 covered)
#   - 20 GB gp3 storage: free tier covers this
#   - single-AZ: multi-AZ doubles the bill
#   - backup_retention_period = 0: skip automated backup cost
#   - skip_final_snapshot = true: terraform destroy works without prompting
#
# Security:
#   - publicly_accessible = false (lives in private subnets, no public DNS)
#   - storage_encrypted = true (uses AWS-managed KMS key, free)
#   - SG accepts traffic only from the Lambda SG
#   - rds.force_ssl = 1 in parameter group rejects unencrypted connections
# ---------------------------------------------------------------------------

# Resolve the current default Postgres 16 minor version dynamically.
# Hardcoding "16.4" or similar is fragile - AWS rotates which patch versions
# are available, and old ones can return "Cannot find version" mid-deploy.
# Asking for the current default makes the config immune to that drift.
data "aws_rds_engine_version" "postgres16" {
  engine                 = "postgres"
  parameter_group_family = "postgres16"
  default_only           = true
}

# Subnet group must cover at least 2 AZs - RDS rule, even for single-AZ
# deployments. We pass both private subnets created in networking.tf.
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  subnet_ids  = aws_subnet.private[*].id
  description = "DB subnet group spanning the 2 private subnets across 2 AZs."

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# Parameter group lets us flip Postgres settings without touching the
# instance. We use it to force SSL on every connection - tiny win, free.
resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-postgres16"
  family      = "postgres16"
  description = "Custom parameters for the ${local.name_prefix} Postgres 16 instance."

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${local.name_prefix}-postgres16"
  }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  # ---- Engine ----
  engine         = "postgres"
  engine_version = data.aws_rds_engine_version.postgres16.version
  instance_class = "db.t3.micro"

  # ---- Storage ----
  allocated_storage     = 20  # free tier covers 20 GB
  max_allocated_storage = 100 # autoscaling cap if usage ever spikes
  storage_type          = "gp3"
  storage_encrypted     = true

  # ---- Database ----
  db_name  = "expense_tracker"
  username = "expense_admin"
  password = random_password.rds_master.result
  port     = 5432

  # ---- Networking ----
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # ---- Config ----
  parameter_group_name = aws_db_parameter_group.main.name

  # ---- Backup / lifecycle (portfolio defaults, not prod) ----
  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  # ---- Monitoring (kept off - both cost money outside free tier) ----
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}
