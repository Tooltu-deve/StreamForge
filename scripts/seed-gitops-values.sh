#!/usr/bin/env bash
# Seed streamforge-gitops/values/*.yaml from live Terraform outputs.
# Usage: GITOPS_DIR=~/…/streamforge-gitops ./scripts/seed-gitops-values.sh
set -euo pipefail

: "${GITOPS_DIR:?set GITOPS_DIR to the streamforge-gitops checkout}"
REGION=ap-southeast-1
ACCOUNT=252773257724
ECR="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/streamforge-dev"
CORE="terraform -chdir=infra/env/dev output -raw"
CORE_JSON="terraform -chdir=infra/env/dev output -json"
PLAT="terraform -chdir=infra/platform/dev output -json svc_role_arns"

TABLE=$($CORE table_name)
RAW=$($CORE_JSON bucket_names | jq -r .raw)
TRANSCODED=$($CORE_JSON bucket_names | jq -r .transcoded)
QUEUE=$($CORE queue_url)
POOL=$($CORE user_pool_id)
CLIENT=$($CORE app_client_id)
ROLES=$(eval "$PLAT")
r() { echo "$ROLES" | jq -r --arg k "$1" '.[$k]'; }

# Preserve any existing image.tag so re-seeding does not clobber a CI-bumped tag.
tag() { local f="$GITOPS_DIR/values/$1.yaml"; [ -f "$f" ] && yq '.image.tag // "dev"' "$f" 2>/dev/null || echo dev; }

cat > "$GITOPS_DIR/values/catalog.yaml" <<EOF
name: catalog
image: { repo: "$ECR/catalog", tag: "$(tag catalog)" }
serviceAccount: { roleArn: "$(r catalog)" }
env:
  REGION: $REGION
  TABLE_NAME: "$TABLE"
rollout: { enabled: true }
EOF

cat > "$GITOPS_DIR/values/upload.yaml" <<EOF
name: upload
image: { repo: "$ECR/upload", tag: "$(tag upload)" }
serviceAccount: { roleArn: "$(r upload)" }
env:
  REGION: $REGION
  RAW_BUCKET: "$RAW"
  TABLE_NAME: "$TABLE"
  COGNITO_POOL_ID: "$POOL"
  COGNITO_CLIENT_ID: "$CLIENT"
EOF

cat > "$GITOPS_DIR/values/playback.yaml" <<EOF
name: playback
image: { repo: "$ECR/playback", tag: "$(tag playback)" }
serviceAccount: { roleArn: "$(r playback)" }
env:
  REGION: $REGION
  RAW_BUCKET: "$RAW"
  TABLE_NAME: "$TABLE"
  COGNITO_POOL_ID: "$POOL"
  COGNITO_CLIENT_ID: "$CLIENT"
EOF

cat > "$GITOPS_DIR/values/transcode-worker.yaml" <<EOF
name: transcode-worker
image: { repo: "$ECR/transcode-worker", tag: "$(tag transcode-worker)" }
serviceAccount: { roleArn: "$(r transcode-worker)" }
env:
  REGION: $REGION
  RAW_BUCKET: "$RAW"
  TRANSCODED_BUCKET: "$TRANSCODED"
  TABLE_NAME: "$TABLE"
  QUEUE_URL: "$QUEUE"
nodeSelector: { workload: transcode }
tolerations:
  - { key: dedicated, operator: Equal, value: transcode, effect: NoSchedule }
keda: { enabled: true, maxReplicas: 4, queueUrl: "$QUEUE" }
EOF

# NOTE: ingress is intentionally NOT managed by GitOps in Phase 4 — it carries an edge
# secret (originSecret) that must not live in the public config repo. Deploy it out-of-band
# with `helm --set` (see runbook phase4 §3); it joins GitOps in Phase 6 via External Secrets.

echo "Seeded values into $GITOPS_DIR/values/"