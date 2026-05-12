# Expense Tracker — AWS Infrastructure

[![Terraform](https://img.shields.io/badge/Terraform-1.10+-7B42BC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Lambda%20%2B%20API%20Gateway%20%2B%20RDS-FF9900.svg?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![OIDC](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions%20OIDC-2088FF.svg?logo=githubactions&logoColor=white)](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Production-grade AWS infrastructure** for the [Expense Tracker API](https://github.com/KevinMM007/expense-tracker-api), defined entirely as Terraform code. One `terraform apply` stands up the whole stack — VPC, RDS, Lambda, API Gateway, OIDC federation for CI/CD — and one `terraform destroy` tears it back down. No console clicking, no drift, no surprise bills.

---

## 🌐 Live demo

**API**: <https://be3lmjhj4b.execute-api.us-east-2.amazonaws.com>
**Health check**: <https://be3lmjhj4b.execute-api.us-east-2.amazonaws.com/api/v1/ping> → `{"status":"ok"}`
**Interactive docs (Swagger UI)**: <https://be3lmjhj4b.execute-api.us-east-2.amazonaws.com/docs>

> ⚠️ Free-tier Lambda has cold-start: the first request after ~15 minutes of inactivity may take 5–10 s. Subsequent calls return in <1 s.

> 🧹 To keep the AWS bill near zero this stack is periodically torn down with `terraform destroy` and rebuilt on demand. If the URL above returns 503, the stack is currently destroyed — see [Cleanup](#-cleanup--cost-control).

### Try it in 30 seconds

```bash
BASE="https://be3lmjhj4b.execute-api.us-east-2.amazonaws.com"

# Register + login
curl -X POST "$BASE/api/v1/auth/register" -H "Content-Type: application/json" \
     -d '{"email":"demo@example.com","password":"password123","full_name":"Demo"}'

TOKEN=$(curl -s -X POST "$BASE/api/v1/auth/login" \
        -d "username=demo@example.com&password=password123" \
        | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# Create a category + an expense + read aggregated report
CAT=$(curl -s -X POST "$BASE/api/v1/categories" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"name":"Food"}' | python -c "import sys,json;print(json.load(sys.stdin)['id'])")

curl -X POST "$BASE/api/v1/expenses" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d "{\"amount\":\"42.50\",\"description\":\"Tacos\",\"spent_on\":\"2026-05-12\",\"category_id\":$CAT}"

curl "$BASE/api/v1/reports/by-category" -H "Authorization: Bearer $TOKEN"
```

---

## 🏗 Architecture

```
                                                                                ┌──────────────────────────┐
            GitHub Actions ──── OIDC AssumeRoleWithWebIdentity ─────►          │   AWS account            │
            (no AWS keys                                                       │   us-east-2              │
            in repo secrets)                                                   │                          │
                                                                               │                          │
                                                                               │   IAM OIDC provider      │
                                                                               │   token.actions.github   │
                                                                               │   .githubusercontent.com │
                                                                               │           │              │
                                                                               │           ▼              │
                                                                               │   IAM role (deploy)      │
                                                                               │   trust pinned to        │
                                                                               │   KevinMM007 repo +      │
                                                                               │   main / PR refs only    │
                                                                               │           │              │
                                                                               │           ▼              │
                                                                               │   docker build           │
                                                                               │   docker push → ECR      │
                                                                               │   lambda update-code     │
                                                                               │                          │
                                                                               └──────────────────────────┘

                                                  ╭──────────────────── public internet ────────────────────╮
                                                  │                                                          │
                                                  ▼                                                          │
                                  ┌──────────────────────────────┐                                          │
                                  │  API Gateway HTTP API v2     │   AWS_PROXY integration, $default stage  │
                                  │  ANY / and ANY /{proxy+}     │                                          │
                                  └──────────────┬───────────────┘                                          │
                                                 │                                                          │
                                                 ▼                                                          │
                       ╭──── VPC 10.0.0.0/16 ────────────────────────────────────╮                          │
                       │                                                          │                          │
                       │   ┌────────────────────────────────────────────┐         │                          │
                       │   │   Lambda function (container image)        │         │                          │
                       │   │   Mangum-wrapped FastAPI, x86_64, 512 MB   │         │                          │
                       │   │   in private subnets (us-east-2a / 2b)     │ ── ENI ─┤                          │
                       │   └────────────────────┬───────────────────────┘         │                          │
                       │                        │ TCP 5432                        │                          │
                       │                        │ (SG: only Lambda SG allowed)    │                          │
                       │                        ▼                                 │                          │
                       │   ┌────────────────────────────────────────────┐         │                          │
                       │   │   RDS PostgreSQL 16 (db.t3.micro)          │         │                          │
                       │   │   private subnet, gp3 20 GB encrypted      │         │                          │
                       │   │   rds.force_ssl = 1                        │         │                          │
                       │   └────────────────────────────────────────────┘         │                          │
                       │                                                          │                          │
                       ╰──────────────────────────────────────────────────────────╯                          │
                                                                                                              │
                            CloudWatch Logs (7-day retention) ◄── Lambda stdout / stderr ────────────────────┤
                            Secrets Manager  ────  RDS master credentials JSON  (not consumed by Lambda)     │
                                                                                                              │
                                                                                                              ▼
```

---

## 🧱 Stack

| Layer | Service | Notes |
|---|---|---|
| Compute | **AWS Lambda** | Container image, 512 MB / 60 s, x86_64, in-VPC |
| API gateway | **API Gateway HTTP API v2** | $default stage, auto-deploy, CORS open |
| Database | **Amazon RDS for PostgreSQL 16** | `db.t3.micro`, gp3, single-AZ, private subnet |
| Registry | **Amazon ECR** | Lifecycle policy keeps 5 most recent images |
| Secrets | **AWS Secrets Manager** | Stores DB master credentials (see [trade-offs](#-trade-offs)) |
| Networking | **VPC** + 2 public + 2 private subnets across 2 AZs | No NAT Gateway by design |
| Logs | **CloudWatch Logs** | 7-day retention |
| Identity | **AWS IAM** | Least-privilege roles + OIDC for CI/CD |
| IaC | **Terraform** `>= 1.10` + AWS provider `~> 5.80` | |
| CI / CD | **GitHub Actions** + **OIDC** | No long-lived AWS access keys anywhere |

---

## 📦 Resources created

A single `terraform apply` creates **~35 AWS resources** across these layers:

| File | Resources |
|---|---|
| `networking.tf` | VPC, Internet Gateway, 2× public + 2× private subnets, 2× route tables, 4× associations |
| `security_groups.tf` | Lambda SG (egress all), RDS SG (ingress 5432 from Lambda SG only) |
| `database.tf` | DB subnet group, parameter group (`rds.force_ssl=1`), RDS instance |
| `secrets.tf` | Random password (32 chars), Secrets Manager secret + version (JSON bundle) |
| `ecr.tf` | ECR repository, lifecycle policy (keep last 5 images) |
| `iam.tf` | Lambda execution role + AWS-managed policies + inline secrets-read policy |
| `compute.tf` | Random JWT secret, CloudWatch log group, Lambda function (container image) |
| `api_gateway.tf` | HTTP API, AWS_PROXY integration, 2 routes, `$default` stage, lambda permission |
| `github_actions.tf` | OIDC provider, deploy role with repo-scoped trust policy, deploy policy |

All resources are tagged with `Project`, `Environment`, `ManagedBy=Terraform`, `Repository` via `provider.tf` default tags, so they show up nicely grouped in **Cost Explorer** and **Tag Editor**.

---

## 🚀 Quickstart

**Pre-requisites:**

- Terraform `>= 1.10`
- AWS CLI v2, configured with an IAM user that can create the resources above
- Docker (for the first manual image push; subsequent deploys go through CI/CD)
- An IAM role on the AWS account with admin or equivalent permissions

```bash
# 1. Clone
git clone https://github.com/KevinMM007/expense-tracker-infra.git
cd expense-tracker-infra

# 2. Verify your AWS identity
aws sts get-caller-identity

# 3. Initialize Terraform (downloads providers, ~30 s)
terraform init

# 4. Preview every resource Terraform will create
terraform plan

# 5. Apply (creates 14 networking resources, costs $0)
terraform apply

# 6. Push the first Lambda image to ECR (after that, CI takes over)
#    see the `expense-tracker-api` repo for the Dockerfile.lambda
docker build --provenance=false --sbom=false --platform linux/amd64 \
    -f ../expense-tracker-api/Dockerfile.lambda \
    -t "$(terraform output -raw ecr_repository_url):latest" \
    ../expense-tracker-api

aws ecr get-login-password --region us-east-2 \
    | docker login --username AWS --password-stdin "$(terraform output -raw ecr_repository_url)"

docker push "$(terraform output -raw ecr_repository_url):latest"

# 7. Apply the rest of the stack (Lambda + API Gateway + IAM + ...)
terraform apply
```

After step 7, `terraform output api_gateway_invoke_url` prints the live URL.

---

## 🔄 CI / CD

The companion repo [`expense-tracker-api`](https://github.com/KevinMM007/expense-tracker-api) has a GitHub Actions workflow ([`aws-deploy.yml`](https://github.com/KevinMM007/expense-tracker-api/blob/main/.github/workflows/aws-deploy.yml)) that runs on every push to `main`:

1. **Pre-deploy tests** — `ruff check`, `alembic upgrade head` against a Postgres service container, `pytest --cov-fail-under=70`.
2. **OIDC handshake** — `aws-actions/configure-aws-credentials` exchanges the GitHub OIDC token for an STS session, _no long-lived AWS keys are stored anywhere in the repo._
3. **Build + push** — `docker build` the Lambda image, tag with both `:<sha>` and `:latest`, push both to ECR.
4. **Update Lambda** — `aws lambda update-function-code --image-uri ...:<sha>`, then `aws lambda wait function-updated`.
5. **Smoke-test** — invoke the function with a synthetic API Gateway v2 `/ping` event, fail the job if `statusCode != 200`.

Trust on the OIDC role (`github_actions.tf`) is pinned to **this exact repo on `main` or in a pull request**. Any other repo or branch can't assume it even though they share the same OIDC provider.

---

## ⚖️ Trade-offs

This is a **portfolio project that stays in AWS Free Tier**. Some decisions favour $0 cost over textbook best practice. Each one is a deliberate, documented choice rather than an oversight.

### 1. No NAT Gateway → DATABASE_URL in Lambda env var (not Secrets Manager fetch)

Lambda is deployed inside the VPC so it can reach RDS over private DNS. That same VPC has _no_ NAT Gateway (which costs ~$35/month minimum). The textbook way to read the DB credentials from Secrets Manager at runtime would require either a NAT Gateway or a Secrets Manager VPC endpoint (~$7/month).

To stay free, Terraform constructs the connection string from the random password and the RDS endpoint and passes it directly as a Lambda env var. The Secrets Manager secret is still created and the Lambda role still has IAM read on it — the upgrade to "production-correct" is one VPC-endpoint resource away.

**Production fix:** add `aws_vpc_endpoint` for `secretsmanager` (~$7/month), drop `DATABASE_URL` from the env vars, and the existing `db_credentials_secret_arn` code path in `app/core/config.py` takes over.

### 2. Single-AZ RDS, no automated backups

`multi_az = false` and `backup_retention_period = 0`. For a portfolio project losing the database is recoverable (`terraform destroy && terraform apply` rebuilds the schema via Alembic on cold start). Production would set both: ~2× the storage + IO cost.

### 3. Mutable image tag (`:latest`), `force_delete = true` on ECR

We overwrite `:latest` on every push and let `terraform destroy` drop the repo even when it has images. In a regulated environment, immutable tags + a deny on `ecr:DeleteRepository` outside the change-management role would be the norm.

### 4. Migrations on cold start

The Lambda handler runs `alembic upgrade head` during init. Adds 1–3 s to cold starts, but the alternative — a separate one-shot migration Lambda invoked from CI/CD — is more moving parts than this scope warrants.

---

## 💰 Cost control

Expected monthly cost while running:

| Service | Free tier coverage | After free tier (us-east-2) |
|---|---|---|
| Lambda (1M req / 400K GB-s) | **forever** | ~$0 at portfolio scale |
| API Gateway HTTP API (1M req) | 12 months | ~$1 per 1M req |
| RDS db.t3.micro (750 h, 20 GB gp3) | 12 months | ~$13 |
| ECR (500 MB storage) | 12 months | ~$0.10 per GB-month |
| Secrets Manager | none | $0.40 / secret-month |
| CloudWatch Logs (5 GB ingestion) | always | $0.50 per GB beyond |
| Data transfer (1 GB out / month) | always | $0.09 / GB beyond |

**While free tier applies:** ~$0.40 / month (just Secrets Manager).
**After 12 months, kept running 24×7:** ~$14–16 / month.

### Cleanup workflow

When you don't need the stack running (no demo, no recruiter session imminent), tear it down:

```bash
terraform destroy
```

Or use the convenience script (Windows PowerShell):

```powershell
.\scripts\destroy.ps1
```

After destroy, only the Terraform state file remains (local, ~30 KB) — **$0 ongoing cost**.

When you need the stack back online for a demo:

```bash
terraform apply              # 5–7 min for the RDS instance to come up
# push the Lambda image (CI/CD does this on the next push to main)
```

Round-trip: stand-up + tear-down = ~15 minutes total, ~$0.05 of actual usage.

---

## 🗂 Repository layout

```
expense-tracker-infra/
├── versions.tf                # Terraform + provider version pins
├── provider.tf                # AWS provider config with default tags
├── locals.tf                  # name_prefix, az_count, vpc_cidr
├── variables.tf               # aws_region, project_name, environment
├── terraform.tfvars           # Non-secret values for this environment
├── outputs.tf                 # api_gateway_invoke_url + IDs of every resource
│
├── networking.tf              # VPC, subnets, IGW, route tables
├── security_groups.tf         # Lambda SG + RDS SG (least-privilege)
├── database.tf                # RDS instance + subnet group + parameter group
├── secrets.tf                 # random_password + Secrets Manager secret/version
├── ecr.tf                     # Container registry + lifecycle policy
├── iam.tf                     # Lambda execution role + policies
├── compute.tf                 # Lambda function + CloudWatch log group + JWT secret
├── api_gateway.tf             # HTTP API + integration + routes + stage + permission
├── github_actions.tf          # OIDC provider + deploy role for GitHub Actions
│
├── scripts/
│   └── destroy.ps1            # Convenience teardown script for Windows
│
├── .terraform.lock.hcl        # Committed: provider checksums for reproducibility
├── .gitignore                 # Ignores .terraform/, *.tfstate, *.auto.tfvars
├── LICENSE                    # MIT
└── README.md                  # ← you are here
```

---

## 📜 License

[MIT](LICENSE)

---

Built by **[Kevin Morales](https://github.com/KevinMM007)** as part of a backend portfolio focused on remote LATAM / USA junior roles.
