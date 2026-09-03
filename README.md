# EPOCH — Session 17.2: GCP Foundation

This directory stands up the **cloud foundation** that Session 17.3 deploys
`epoch-gateway` onto. It does not touch application code or the container image
itself (that was Session 17.1) — it gives that image **a home** (Artifact
Registry) and **an identity** (a least-privilege service account) inside a real
GCP project.

By the end you have:

| Piece | What it is | Why 17.3 needs it |
|---|---|---|
| **GCP project** + billing | The container everything attaches to | Nothing can be created without it |
| **4 enabled APIs** | `run`, `artifactregistry`, `secretmanager`, `sqladmin` | Each GCP service is off by default |
| **Artifact Registry repo** `epoch-images` | A private Docker registry in one region | Cloud Run pulls the image from here |
| **Image** `epoch-api:v1` pushed to that repo | The Session 17.1 container, now in the cloud | This is what 17.3 deploys |
| **Service account** `epoch-gateway-sa` | A robot identity the gateway runs as | So the deploy does **not** fall back to the default compute SA (which has `roles/editor`) |
| **Exactly 4 IAM roles** on that SA | `secretmanager.secretAccessor`, `run.invoker`, `storage.objectViewer`, `cloudsql.client` | The gateway's complete runtime permission set — nothing more |

---

## The core doctrine: exactly four roles

The service account gets **four** project-level role bindings and no others.
This is the same least-privilege principle from Session 15.2's compiler-level
RBAC, applied to infrastructure identity.

| Role | Why the gateway needs it |
|---|---|
| `roles/secretmanager.secretAccessor` | Read `GEMINI_API_KEY` / `JWT_SECRET` from Secret Manager at boot |
| `roles/run.invoker` | Call other internal Cloud Run services |
| `roles/storage.objectViewer` | Read trace files from the GCS traces bucket |
| `roles/cloudsql.client` | Connect to Postgres through the Cloud SQL proxy |

**No `roles/editor`, no `roles/owner`, no `roles/storage.admin`.** A fifth role
bound "just in case" — even something as narrow as `roles/logging.viewer` —
fails `verify.sh`. Add a role only when 17.3 proves the gateway needs it at
runtime.

---

## Files

| File | Responsibility |
|---|---|
| `setup_gcp.sh` | Orchestrator: enables the 4 APIs, then runs the two scripts below |
| `create_registry.sh` | Creates the Artifact Registry repo, tags `epoch-api:v1`, pushes it |
| `iam_bindings.sh` | Creates `epoch-gateway-sa`, binds exactly the 4 roles |
| `verify.sh` | The graded checks — image present, SA exists, exactly 4 bindings, no editor/owner |
| `.epoch_state/` | Manifest written by **dry-run** mode; git-ignored |

All three setup scripts are **idempotent** — safe to re-run. They check whether
a resource exists before creating it.

### Configuration (environment variables)

| Var | Default | Notes |
|---|---|---|
| `GCP_PROJECT` | `epoch-prod` | The literal string. **Override this** — real project IDs are globally unique (e.g. `epoch-prod-762035`). |
| `GCP_REGION` | `us-central1` | Must match the eventual 17.3 Cloud Run region. Keep it consistent across all scripts. |
| `DRY_RUN` | `0` | `1` (or the `--dry-run` flag) prints every `gcloud`/`docker` call instead of running it. |

---

## Step-by-step: reproduce this on a clean machine

### 0. Prerequisites

- **macOS or Linux** with a shell
- **Docker** running, with the Session 17.1 image built locally:
  ```bash
  docker images epoch-api:v1        # must show a row
  ```
  If it is missing, complete Session 17.1 first (`cd epoch-gateway && bash verify.sh`).
- **A Google account** with a **billing account** (new accounts get $300 / 90 days
  of free credit; a card must be on file). This build costs ~$0/month — a
  ~226 MB image is about 2¢/month of registry storage; SA, IAM, and API
  enablement are free.

### 1. Install the gcloud CLI

**macOS (Homebrew):**
```bash
brew install --cask google-cloud-sdk
```
**Linux / other:** https://cloud.google.com/sdk/docs/install

Verify:
```bash
gcloud --version
```

### 2. Authenticate

```bash
gcloud auth login
```
A browser opens → pick your account → **Allow**. If no browser is available:
```bash
gcloud auth login --no-launch-browser
```

### 3. Create a project and link billing

```bash
# Pick a globally-unique ID. "epoch-prod" alone is almost certainly taken.
PROJECT_ID="epoch-prod-$RANDOM"
gcloud projects create "$PROJECT_ID" --name="EPOCH Prod" --set-as-default

# Find your billing account ID
gcloud billing accounts list

# Link it (replace with the ID from the previous command)
gcloud billing projects link "$PROJECT_ID" --billing-account=XXXXXX-XXXXXX-XXXXXX

# Confirm
gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)"   # -> True
```

### 4. Run the foundation setup

```bash
cd epoch-gcp
export GCP_PROJECT="$PROJECT_ID"
export GCP_REGION="us-central1"
bash setup_gcp.sh
```

Expected tail:
```
✓ run.googleapis.com
✓ artifactregistry.googleapis.com
✓ secretmanager.googleapis.com
✓ sqladmin.googleapis.com
✓ epoch-images created in us-central1
✓ pushed: us-central1-docker.pkg.dev/<project>/epoch-images/epoch-api:v1
✓ epoch-gateway-sa@<project>.iam.gserviceaccount.com
✓ roles/secretmanager.secretAccessor
✓ roles/run.invoker
✓ roles/storage.objectViewer
✓ roles/cloudsql.client
Foundation ready for 17.3 deploy.
```

### 5. Verify

```bash
bash verify.sh
```
```
✓ image present in Artifact Registry: epoch-api:v1
✓ service account exists: epoch-gateway-sa
✓ service account has exactly 4 IAM bindings, no more
✓ no default compute service account in use
✓ Session 17.2 COMPLETE.
```

---

## Dry-run mode (no GCP account, no cost)

Every setup script accepts `--dry-run` (or `DRY_RUN=1`). It prints each cloud
call, runs none of them, and records a manifest under `.epoch_state/`.
`verify.sh` automatically reads that manifest when `gcloud` is absent or
`DRY_RUN=1` is set. The grader accepts dry-run output.

```bash
cd epoch-gcp
bash setup_gcp.sh --dry-run
bash verify.sh          # validates the .epoch_state/ manifest
```

---

## The two graded checks

| # | Check | Command | Pass criteria |
|---|---|---|---|
| 1 | Image lives in the registry | `gcloud artifacts docker images list …` | `epoch-api:v1` present |
| 2 | SA has exactly 4 roles | `gcloud projects get-iam-policy …` | exactly 4 bindings, none over-privileged |

Manual audit:
```bash
gcloud artifacts docker images list \
  "us-central1-docker.pkg.dev/$GCP_PROJECT/epoch-images" --include-tags

gcloud projects get-iam-policy "$GCP_PROJECT" \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:epoch-gateway-sa@$GCP_PROJECT.iam.gserviceaccount.com" \
  --format="value(bindings.role)" | sort
```

---

## Common failure modes

1. **Deploying against the default compute service account.** Every project
   ships `<num>-compute@developer.gserviceaccount.com` with `roles/editor`
   pre-bound. If `iam_bindings.sh` never runs, 17.3's deploy silently succeeds
   *using that identity*. 17.3 checks the deploy's `--service-account` flag, so
   the scoped SA must both exist **and** be passed explicitly.
2. **Reaching for GKE out of habit.** `epoch-gateway` is stateless and bursty →
   **Cloud Run**. Not GKE, not Compute Engine. `setup_gcp.sh` enables
   `run.googleapis.com` for exactly this reason.
3. **Region drift.** Registry, SA, and the eventual Cloud Run service must share
   a region. Keep `GCP_REGION` identical across every script and the 17.3
   deploy, or you add latency now and break `--region` pinning later.

---

## Troubleshooting

**`Permission denied` creating `~/.config/gcloud`** — the config directory is
not writable (some managed machines have it owned by root). Point gcloud
elsewhere:
```bash
export CLOUDSDK_CONFIG="$HOME/.gcloud"
mkdir -p "$HOME/.gcloud"
```
Add that `export` to your shell profile so it persists.

**`docker push` → `denied` / `unauthorized`** — the credential helper is not
configured. `create_registry.sh` runs `gcloud auth configure-docker
<region>-docker.pkg.dev --quiet`; if you run steps by hand, run that first, and
make sure `docker-credential-gcloud` is on your `PATH`.

**`gcloud projects create` → `already exists`** — the project ID is globally
unique across all of GCP. Pick another.

**`gcloud services enable` → billing error** — the project has no billing
account linked. Redo step 3.

---

## This project's live values (Session 17.2 run, 2026-09-03)

| | |
|---|---|
| Project ID | `epoch-prod-762035` (number `790474061821`) |
| Region | `us-central1` |
| Image | `us-central1-docker.pkg.dev/epoch-prod-762035/epoch-images/epoch-api:v1` |
| Service account | `epoch-gateway-sa@epoch-prod-762035.iam.gserviceaccount.com` |

Run the scripts with `GCP_PROJECT=epoch-prod-762035`.

---

## Next: Session 17.3

Deploy `epoch-api:v1` to Cloud Run in `us-central1` with
`--service-account=epoch-gateway-sa@epoch-prod-762035.iam.gserviceaccount.com`.
Also required before that deploy:

- a Cloud SQL Postgres instance
- Secret Manager secrets `GEMINI_API_KEY` and `JWT_SECRET`
- a GCS bucket for trace files
