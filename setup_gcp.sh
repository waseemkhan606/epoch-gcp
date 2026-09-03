#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# setup_gcp.sh — orchestrates the 17.2 foundation:
#   1. enable the four APIs 17.3 needs
#   2. create_registry.sh  -> Artifact Registry repo + push epoch-api:v1
#   3. iam_bindings.sh      -> epoch-gateway-sa + exactly 4 IAM roles
#
# Compute decision (from the deck's Cloud Run vs GKE vs Compute Engine table):
#   epoch-gateway is stateless and bursty -> Cloud Run. Not GKE, not GCE.
#
# Env / flags:
#   GCP_PROJECT   (default: epoch-prod)
#   GCP_REGION    (default: us-central1)
#   DRY_RUN=1  or  --dry-run   -- propagates to the child scripts
# ---------------------------------------------------------------------------

PROJECT="${GCP_PROJECT:-epoch-prod}"
REGION="${GCP_REGION:-us-central1}"

DRY_RUN="${DRY_RUN:-0}"
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
export DRY_RUN GCP_PROJECT="$PROJECT" GCP_REGION="$REGION"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EPOCH_STATE_DIR="${EPOCH_STATE_DIR:-$HERE/.epoch_state}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

run gcloud config set project "$PROJECT" --quiet

echo "Enabling APIs..."
APIS=(run.googleapis.com artifactregistry.googleapis.com \
      secretmanager.googleapis.com sqladmin.googleapis.com)
for API in "${APIS[@]}"; do
  run gcloud services enable "$API" --quiet
  echo "✓ ${API}"
done

echo ""
bash "$HERE/create_registry.sh"

echo ""
bash "$HERE/iam_bindings.sh"

echo ""
echo "Foundation ready for 17.3 deploy."
