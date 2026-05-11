locals {
  # Resource naming convention: <project>-<env>-<resource>
  # Example: expense-tracker-dev-vpc, expense-tracker-dev-rds
  name_prefix = "${var.project_name}-${var.environment}"

  # Number of Availability Zones to spread subnets across.
  # RDS requires a DB subnet group covering at least 2 AZs even when running
  # in single-AZ mode, so 2 is the minimum.
  az_count = 2

  # IPv4 address space for the VPC. /16 = 65 536 addresses — far more than
  # we need, but keeps subnet math comfortable and leaves room to grow.
  vpc_cidr = "10.0.0.0/16"
}
