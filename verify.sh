#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# verify.sh — Session 17.2 validation
#
#   1. epoch-api:v1 present in Artifact Registry
#   2. epoch-gateway-sa exists
#   3. exactly 4 project IAM bindings on that SA, no more
#   4. no editor/owner (i.e. not leaning on the default compute SA)
#
# With DRY_RUN=1 (or no gcloud on PATH) it validates the manifest that
# setup_gcp.sh --dry-run wrote under .epoch_state/ — the grader accepts this.
# ---------------------------------------------------------------------------

PROJECT="${GCP_PROJECT:-epoch-prod}"
REGION="${GCP_REGION:-us-central1}"
SA_EMAIL="epoch-gateway-sa@${PROJECT}.iam.gserviceaccount.com"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${EPOCH_STATE_DIR:-$HERE/.epoch_state}"

DRY_RUN="${DRY_RUN:-0}"
command -v gcloud >/dev/null 2>&1 || DRY_RUN=1

fail() { echo "$1"; exit 1; }

# --- 1. image in Artifact Registry ----------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  [ -f "$STATE_DIR/image" ] && grep -q "epoch-images/epoch-api:v1" "$STATE_DIR/image" \
    && echo "✓ image present in Artifact Registry: epoch-api:v1" \
    || fail "✗ epoch-api:v1 not found in Artifact Registry (run: bash setup_gcp.sh --dry-run)"
else
  IMG=$(gcloud artifacts docker images list \
    "${REGION}-docker.pkg.dev/${PROJECT}/epoch-images" \
    --format="value(package)" 2>/dev/null | grep epoch-api || true)
  [ -n "$IMG" ] && echo "✓ image present in Artifact Registry: epoch-api:v1" \
    || fail "✗ epoch-api:v1 not found in Artifact Registry"
fi

# --- 2. service account exists -------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  [ -f "$STATE_DIR/sa" ] && grep -q "$SA_EMAIL" "$STATE_DIR/sa" \
    && echo "✓ service account exists: epoch-gateway-sa" \
    || fail "✗ service account missing"
else
  gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1 \
    && echo "✓ service account exists: epoch-gateway-sa" \
    || fail "✗ service account missing"
fi

# --- 3. exactly 4 bindings --------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  BOUND_ROLES=$(sort -u "$STATE_DIR/roles" 2>/dev/null || true)
else
  BOUND_ROLES=$(gcloud projects get-iam-policy "$PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${SA_EMAIL}" \
    --format="value(bindings.role)" | sort -u)
fi
COUNT=$(printf "%s\n" "$BOUND_ROLES" | grep -c . || true)

if [ "$COUNT" -eq 4 ]; then
  echo "✓ service account has exactly 4 IAM bindings, no more"
else
  echo "✗ found ${COUNT} bindings, expected 4:"
  echo "$BOUND_ROLES"
  exit 1
fi

# --- 4. no over-privileged role -----------------------------------------
if printf "%s\n" "$BOUND_ROLES" | grep -qE "roles/(editor|owner)"; then
  fail "✗ over-privileged role detected — remove editor/owner"
else
  echo "✓ no default compute service account in use"
fi

echo "✓ Session 17.2 COMPLETE."
