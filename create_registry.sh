#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# create_registry.sh — Artifact Registry repo + tag + push of epoch-api:v1
#
# Env / flags:
#   GCP_PROJECT   (default: epoch-prod)
#   GCP_REGION    (default: us-central1)   -- keep consistent with 17.3 deploy
#   DRY_RUN=1  or  --dry-run               -- print gcloud/docker calls, run none
# ---------------------------------------------------------------------------

PROJECT="${GCP_PROJECT:-epoch-prod}"
REGION="${GCP_REGION:-us-central1}"
REPO="epoch-images"
IMAGE_LOCAL="epoch-api:v1"
IMAGE_REMOTE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/epoch-api:v1"

DRY_RUN="${DRY_RUN:-0}"
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

STATE_DIR="${EPOCH_STATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.epoch_state}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

echo "Creating Artifact Registry repo..."
if [ "$DRY_RUN" = "1" ]; then
  run gcloud artifacts repositories create "$REPO" \
    --repository-format=docker --location="$REGION" \
    --description="EPOCH production images"
else
  gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$REPO" \
      --repository-format=docker \
      --location="$REGION" \
      --description="EPOCH production images"
fi
echo "✓ ${REPO} created in ${REGION}"

run gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo ""
echo "Tagging and pushing ${IMAGE_LOCAL}..."
run docker tag "$IMAGE_LOCAL" "$IMAGE_REMOTE"
run docker push "$IMAGE_REMOTE"
echo "✓ pushed: ${IMAGE_REMOTE}"

if [ "$DRY_RUN" = "1" ]; then
  mkdir -p "$STATE_DIR"
  echo "$IMAGE_REMOTE" > "$STATE_DIR/image"
fi
