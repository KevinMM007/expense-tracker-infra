variable "aws_region" {
  description = "AWS region where all resources are deployed. Stick to one region for free-tier eligibility and to keep latency / egress costs low."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short identifier used as a prefix for resource names and tags. Lowercase, hyphenated."
  type        = string
  default     = "expense-tracker"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 chars, lowercase, start with a letter, and contain only a-z, 0-9, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming and lets us run dev / staging / prod from the same code base."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
