#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"

echo "This will DESTROY all '$ENV' infrastructure."
read -r -p "Type the environment name ('$ENV') to confirm: " CONFIRM
if [ "$CONFIRM" = "$ENV" ]; then
  make destroy ENV="$ENV"
else
  echo "Confirmation did not match. Aborted."
  exit 1
fi