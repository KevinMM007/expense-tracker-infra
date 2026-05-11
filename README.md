# Expense Tracker — AWS Infrastructure

[![Terraform](https://img.shields.io/badge/Terraform-1.10+-7B42BC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Lambda%20%2B%20API%20Gateway%20%2B%20RDS-FF9900.svg?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Production-grade AWS infrastructure** for the [Expense Tracker API](https://github.com/KevinMM007/expense-tracker-api), defined entirely as Terraform code. One command stands the whole stack up, one command tears it back down — exactly how cloud infrastructure should be managed.

> Status: 🚧 in active development.

---

## 🏗 Architecture

```
                  internet
                     │
                     ▼
          ┌──────────────────────┐
          │  API Gateway HTTP API│   public HTTPS endpoint
          └──────────┬───────────┘
                     │
          ┌──────────▼───────────┐
          │   AWS Lambda         │   FastAPI via Mangum adapter
          │   (reuses the same   │   same image as the Render deployment
          │    container as the  │   of the Expense Tracker API
          │    Render deploy)    │
          └──────────┬───────────┘
                     │
          ┌──────────▼───────────┐
          │   RDS PostgreSQL 16  │   private subnets, free-tier eligible
          │                      │   db.t3.micro / 20 GB gp3
          └──────────────────────┘

    Secrets Manager · CloudWatch Logs · IAM least-privilege · VPC + SG
```

---

## 🧱 Stack

| Layer | Service |
|---|---|
| Compute | **AWS Lambda** (FastAPI via [Mangum](https://github.com/jordaneremieff/mangum) adapter) |
| API gateway | **AWS API Gateway HTTP API** |
| Database | **Amazon RDS for PostgreSQL 16** (private subnets) |
| Networking | **VPC** + public / private subnets + security groups |
| Secrets | **AWS Secrets Manager** |
| Logs / metrics | **AWS CloudWatch** |
| IaC | **Terraform** `>= 1.10` + AWS provider `~> 5.80` |
| CI / CD | **GitHub Actions** with **OIDC** (no long-lived AWS keys in the repo) |

---

## 🚀 Quickstart

```bash
# 1. Clone
git clone https://github.com/KevinMM007/expense-tracker-infra.git
cd expense-tracker-infra

# 2. Configure AWS credentials (one-time, per workstation)
aws configure

# 3. Initialize Terraform — downloads providers, sets up the working dir
terraform init

# 4. Preview every change Terraform is about to make
terraform plan

# 5. Apply — creates the entire stack on AWS
terraform apply

# 6. When you're done demoing, tear it all down
terraform destroy
```

---

## 💰 Cost model

Designed to live inside the **AWS Free Tier**, which on a fresh account covers:

- Lambda — **1M requests** + 400K GB-seconds compute, free **forever**
- API Gateway HTTP API — **1M requests/month**, free 12 months
- RDS `db.t3.micro` — **750 hours/month**, free 12 months
- 20 GB gp3 storage — free 12 months

**Expected monthly bill while free tier applies:** ~$0–2 USD.
**After 12 months (if kept running 24/7):** ~$15 USD/month.

> **Tip:** run `terraform destroy` between demos. Stand-up + tear-down round trip is ~10 minutes. Cost while torn down: literal pennies (just S3 state storage).

---

## 🗂 Repository layout

```
expense-tracker-infra/
├── versions.tf          # Terraform + provider version pins
├── provider.tf          # AWS provider config with default tags
├── variables.tf         # Input variable declarations + validation
├── terraform.tfvars     # Non-secret values for this deployment
├── outputs.tf           # Exported attributes (api URL, db endpoint, etc.)
├── .gitignore           # Ignores .terraform/, *.tfstate, *.auto.tfvars, ...
└── README.md            # ← you are here
```

Resource modules (networking, database, compute, api) will be added as `*.tf` files at the root as the project grows. Refactor into `modules/` only when the file count justifies it — not on day one.

---

## 📜 License

[MIT](LICENSE)

---

Built by **[Kevin Morales](https://github.com/KevinMM007)** — backend portfolio focused on remote LATAM / USA junior roles.
