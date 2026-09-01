#!/usr/bin/env bash
#
# One-time bootstrap: creates the S3 bucket that holds Terraform remote
# state for all other stacks. Run this ONCE, by hand, before anything else.
#
# Usage:
#   ./scripts/bootstrap.sh
#
# Requires: terraform >= 1.10, aws CLI configured with an identity that can
# create S3 buckets and KMS keys.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/../infrastructure/bootstrap"

cd "$BOOTSTRAP_DIR"

if [ ! -f terraform.tfvars ]; then
  echo "No terraform.tfvars found."
  echo "Copy terraform.tfvars.example to terraform.tfvars and set a globally-unique state_bucket_name first."
  exit 1
fi

echo "==> Initializing bootstrap stack (local state)"
terraform init

echo "==> Planning bootstrap stack"
terraform plan -out=bootstrap.tfplan

echo
read -r -p "Apply the plan above and create the Terraform state bucket? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

terraform apply bootstrap.tfplan
rm -f bootstrap.tfplan

BUCKET=$(terraform output -raw state_bucket_name)

echo
echo "==> Bootstrap complete."
echo "State bucket: $BUCKET"
echo
echo "Next steps:"
echo "  1. Update the 'bucket' value in infrastructure/envs/staging/backend.tf and"
echo "     infrastructure/envs/prod/backend.tf (and providers.tf's terraform_remote_state"
echo "     block in prod) to: $BUCKET"
echo "  2. cd infrastructure/envs/staging && terraform init"
