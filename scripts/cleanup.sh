#!/usr/bin/env bash
#
# Safely tears down a full environment (staging or prod) to stop AWS
# charges. Does NOT delete the Terraform state bucket / bootstrap stack —
# that is left in place so you can re-deploy later. Run cleanup for prod
# before staging if you deploy in that order, since prod's ECR/OIDC lookups
# reference staging's remote state.
#
# Usage:
#   ./scripts/cleanup.sh staging
#   ./scripts/cleanup.sh prod
#
# This DESTROYS (permanently deletes):
#   - VPC, subnets, NAT Gateway, route tables, security groups
#   - Application Load Balancer and target group
#   - ECS cluster, service, task definitions (running tasks stopped)
#   - RDS instance (staging: no final snapshot. prod: a final snapshot IS
#     taken, since skip_final_snapshot = false there — it is NOT deleted
#     by this script and will continue to incur storage charges until you
#     remove it manually)
#   - CloudWatch log groups, dashboards, alarms, SNS topic
#   - IAM roles created for this environment (task role, execution role,
#     GitHub Actions deploy role — but NOT the shared GitHub OIDC provider
#     if this is prod, since staging owns it)
#
# This does NOT destroy:
#   - The Terraform state S3 bucket (infrastructure/bootstrap)
#   - The ECR repository or any images in it (owned by staging only;
#     destroying staging will prompt to destroy it too — read the plan
#     output carefully)

set -euo pipefail

ENV="${1:-}"

if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 <staging|prod>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../infrastructure/envs/$ENV"

cd "$ENV_DIR"

echo "==> Working directory: $ENV_DIR"
echo "==> Generating destroy plan for '$ENV'..."
terraform init -input=false
terraform plan -destroy -out=destroy.tfplan

echo
echo "The plan above will PERMANENTLY DELETE the resources listed."
if [ "$ENV" == "prod" ]; then
  echo "*** THIS IS PRODUCTION. Double-check you intend to tear it down. ***"
fi
echo
read -r -p "Type the environment name ('$ENV') to confirm destroy: " confirm

if [ "$confirm" != "$ENV" ]; then
  echo "Confirmation did not match. Aborted, nothing was destroyed."
  rm -f destroy.tfplan
  exit 1
fi

terraform apply destroy.tfplan
rm -f destroy.tfplan

echo
echo "==> $ENV environment destroyed."
echo "Reminder: the Terraform state bucket (infrastructure/bootstrap) was NOT touched."
if [ "$ENV" == "prod" ]; then
  echo "Reminder: a final RDS snapshot was created for prod and still incurs storage cost."
  echo "List with: aws rds describe-db-snapshots --db-instance-identifier devops-portfolio-prod-postgres"
fi
