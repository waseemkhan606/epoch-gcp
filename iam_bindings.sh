#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# iam_bindings.sh — runtime service account + EXACTLY 4 project IAM bindings
#
# The gateway is a stateless Cloud Run service. It needs, and gets, only:
#   roles/secretmanager.secretAccessor  read GEMINI_API_KEY / JWT_SECRET at boot
#   roles/run.invoker                   call other internal Cloud Run services
#   roles/storage.objectViewer          read trace files from the GCS bucket
#   roles/cloudsql.client               connect to Postgres via Cloud SQL proxy
#
# No editor. No owner. No storage.admin. A 5th "just in case" role fails 17.2.
#
# Env / flags:
#   GCP_PROJECT   (default: epoch-prod)
#   DRY_RUN=1  or  --dry-run
# ---------------------------------------------------------------------------

PROJECT="${GCP_PROJECT:-epoch-prod}"
SA_NAME="epoch-gateway-sa"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

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

ROLES=(
  "roles/secretmanager.secretAccessor"
  "roles/run.invoker"
  "roles/storage.objectViewer"
  "roles/cloudsql.client"
)

echo "Creating service account..."
if [ "$DRY_RUN" = "1" ]; then
  run gcloud iam service-accounts create "$SA_NAME" --display-name="EPOCH Gateway Runtime"
else
  gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1 || \
    gcloud iam service-accounts create "$SA_NAME" \
      --display-name="EPOCH Gateway Runtime"
fi
echo "✓ ${SA_EMAIL}"

echo ""
echo "Binding IAM roles..."
for ROLE in "${ROLES[@]}"; do
  run gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --condition=None \
    --quiet
  echo "✓ ${ROLE}"
done

if [ "$DRY_RUN" = "1" ]; then
  mkdir -p "$STATE_DIR"
  echo "$SA_EMAIL" > "$STATE_DIR/sa"
  printf "%s\n" "${ROLES[@]}" | sort -u > "$STATE_DIR/roles"
fi
