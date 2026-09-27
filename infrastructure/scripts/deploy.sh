#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"

command -v terraform >/dev/null || { echo "terraform is not installed"; exit 1; }
command -v aws >/dev/null || { echo "aws cli is not installed"; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "AWS credentials not configured"; exit 1; }

echo "==> Step 1: validating and planning for '$ENV'"
make plan ENV="$ENV"

echo "==> Step 2: review the plan above."
read -r -p "Apply this plan to '$ENV'? (yes/no) " CONFIRM
if [ "$CONFIRM" = "yes" ]; then
  make apply ENV="$ENV"
  echo "==> Step 3: outputs"
  make output
else
  echo "Aborted. No changes applied."
fi