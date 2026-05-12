# Convenience teardown script for Windows PowerShell.
#
# Drops every AWS resource managed by this Terraform config and brings the
# ongoing monthly cost down to ~$0 (only the local state file remains).
#
# Usage:
#   .\scripts\destroy.ps1            # interactive confirmation
#   .\scripts\destroy.ps1 -Force     # skip confirmation
#
# After running, re-creating the stack is one `terraform apply` away
# (~5-7 min, dominated by RDS provisioning).

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Make sure we're at the repo root (where provider.tf lives) so terraform
# picks up the right .tf files.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    if (-not (Test-Path "provider.tf")) {
        Write-Host "Error: provider.tf not found in $RepoRoot." -ForegroundColor Red
        Write-Host "Run this script from inside the expense-tracker-infra repository."
        exit 1
    }

    if (-not $Force) {
        Write-Host ""
        Write-Host "About to DESTROY all AWS resources in this stack:" -ForegroundColor Yellow
        Write-Host "  - RDS Postgres instance  (DATABASE CONTENTS WILL BE LOST)"
        Write-Host "  - Lambda function and CloudWatch logs"
        Write-Host "  - API Gateway HTTP API"
        Write-Host "  - ECR repository AND ALL IMAGES inside it"
        Write-Host "  - Secrets Manager secret"
        Write-Host "  - VPC, subnets, route tables, security groups"
        Write-Host "  - IAM roles and policies (including the OIDC deploy role)"
        Write-Host ""
        Write-Host "Local Terraform state stays on this machine and lets you"
        Write-Host "re-create everything later with 'terraform apply'."
        Write-Host ""

        $confirmation = Read-Host "Type 'destroy' (lowercase, no quotes) to proceed"
        if ($confirmation -ne "destroy") {
            Write-Host "Aborted - nothing changed." -ForegroundColor Green
            exit 0
        }
    }

    Write-Host ""
    Write-Host "Running terraform destroy ..." -ForegroundColor Cyan
    terraform destroy -auto-approve

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "terraform destroy exited with code $LASTEXITCODE." -ForegroundColor Red
        Write-Host "Common causes:"
        Write-Host "  - ECR images blocking the repo delete (force_delete=true should handle this)"
        Write-Host "  - A Lambda ENI still attached to the VPC (Lambda takes a few min to release them)"
        Write-Host "  - Drift between local state and AWS - try 'terraform refresh' then re-run"
        exit $LASTEXITCODE
    }

    Write-Host ""
    Write-Host "All resources destroyed. Ongoing AWS cost is now ~`$0/month." -ForegroundColor Green
    Write-Host "Rebuild with: terraform apply"
}
finally {
    Pop-Location
}
