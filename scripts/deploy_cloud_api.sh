#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 3D Craft - Cloud Run Backend Deployment Script
# -----------------------------------------------------------------------------

PROJECT_ID="forma-studio-2026"
REGION="us-central1"
SERVICE_NAME="craft-api"

cd "$(dirname "$0")/.."

echo "=========================================================="
echo "  Deploying 3D Craft Backend to Google Cloud Run"
echo "  Project: $PROJECT_ID | Service: $SERVICE_NAME"
echo "=========================================================="

echo ""
echo "==> Step 1: Building container image via Google Cloud Build..."
gcloud builds submit --config=deploy/cloud-api/cloudbuild.yaml --project="$PROJECT_ID" .

echo ""
echo "==> Step 2: Finding the latest container image tag..."
LATEST_IMAGE=$(gcloud artifacts docker images list "us-central1-docker.pkg.dev/$PROJECT_ID/craft-cloud/api" \
  --sort-by=~CREATE_TIME \
  --limit=1 \
  --format="value(IMAGE)")

if [ -z "$LATEST_IMAGE" ]; then
  echo "Error: Could not retrieve latest image from Artifact Registry."
  exit 1
fi

echo "Deploying image: $LATEST_IMAGE"

echo ""
echo "==> Step 3: Deploying revision to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image="$LATEST_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --quiet

echo ""
echo "==> Step 4: Health check..."
curl -s "https://3d-craft.web.app/api/health" | grep -q '"ok"' \
  && echo "✅ Live deployment successful! Service is healthy on https://3d-craft.web.app" \
  || echo "⚠️ Deployed! Check status at https://3d-craft.web.app/api/health"
