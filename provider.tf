provider "aws" {
  region = var.aws_region

  # Tags applied automatically to every taggable resource Terraform creates.
  # Makes it trivial to identify and clean up resources later, and to attribute
  # costs in AWS Cost Explorer.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "github.com/KevinMM007/expense-tracker-infra"
    }
  }
}
