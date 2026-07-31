# Runbook — Phase 3a: Core Transcode Pipeline

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it. This builds on `phase2b.md` — only the transcode-specific pieces are covered here.

## 1. Phase objective
After an upload, auto-transcode the video to a 3-rung HLS ladder (360/720/1080) + thumbnail and make it watchable with ABR over `https://app.<domain>`. Pipeline: `S3 raw → EventBridge → SQS(+DLQ) → FFmpeg worker (EKS) → S3 transcoded → DynamoDB status=ready → playback → hls.js`.

## 2. Prerequisites
- Phase 2b deployed (core + platform + edge + services + ingress + CloudFront) — see `phase2b.md`.
- Same shared env:
  ```bash
  export REGION=ap-southeast-1 ACCOUNT=252773257724
  export ECR=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/streamforge-dev
  export NS=streamforge
  ```

## 3. How to provision (Deploy) — additive to the 2b order
```bash
# 1. Core — adds the SQS module + raw-bucket EventBridge notification + event rule
terraform -chdir=infra/env/dev apply

# 2. Platform — adds the transcode-worker IRSA role
terraform -chdir=infra/platform/dev apply

# 3. Build + push the worker image (arm64 host -> force amd64; ffmpeg makes this build ~minutes)
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
export TAG=sha-$(git rev-parse --short=12 HEAD)
docker build --platform linux/amd64 -f services/transcode-worker/Dockerfile -t $ECR/transcode-worker:$TAG services/
docker push $ECR/transcode-worker:$TAG

# 4. Deploy the worker (dedicated chart: no Service/probes)
RAW=$(terraform      -chdir=infra/env/dev output -json bucket_names | jq -r .raw)
TRANSCODED=$(terraform -chdir=infra/env/dev output -json bucket_names | jq -r .transcoded)
TABLE=$(terraform    -chdir=infra/env/dev output -raw table_name)
QUEUE=$(terraform    -chdir=infra/env/dev output -raw queue_url)
R_W=$(terraform -chdir=infra/platform/dev output -json svc_role_arns | jq -r '."transcode-worker"')
helm upgrade --install transcode-worker charts/worker -n $NS \
  --set name=transcode-worker --set image.repo=$ECR/transcode-worker --set image.tag=$TAG \
  --set serviceAccount.roleArn=$R_W \
  --set env.REGION=$REGION --set env.RAW_BUCKET=$RAW --set env.TRANSCODED_BUCKET=$TRANSCODED \
  --set env.TABLE_NAME=$TABLE --set env.QUEUE_URL=$QUEUE

# 5. Edge — adds the /hls/* + /thumbs/* CloudFront behaviors (transcoded origin + OAC)
terraform -chdir=infra/edge/dev apply

# 6. Redeploy playback with APP_DOMAIN so it returns CloudFront HLS URLs
helm upgrade playback charts/service -n $NS --reuse-values --set env.APP_DOMAIN=app.tooltu.io.vn

# 7. Rebuild + resync the frontend (hls.js player)
cd frontend && npm ci && npm run build && aws s3 sync dist/ s3://streamforge-dev-frontend --delete
DIST=$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0]=='app.tooltu.io.vn'].Id" --output text)
aws cloudfront create-invalidation --distribution-id $DIST --paths "/*"; cd ..
```

## 4. How to verify (DoD)
```bash
kubectl -n $NS logs deploy/transcode-worker -f     # watch it pick up a message
```
In the browser at `https://app.tooltu.io.vn`: **upload a video** → wait → the worker log shows it processing → then:
```bash
aws dynamodb get-item --table-name $TABLE \
  --key '{"PK":{"S":"VIDEO#<id>"},"SK":{"S":"METADATA"}}' \
  --query 'Item.{status:status.S,hls:hls_key.S,thumb:thumbnail_key.S}'
```
Expect `status=ready`, `hls_key=hls/<id>/master.m3u8`, `thumbnail_key=thumbs/<id>.jpg`. Click **watch** → the video plays and hls.js switches renditions on the network (dev-tools shows `.m3u8` + `.ts` fetches from `/hls/...`); the thumbnail renders.

Checklist:
- [ ] Upload → auto-transcode (no manual step).
- [ ] `status=ready` + `hls_key` + `thumbnail_key` in DynamoDB.
- [ ] ABR playback over the domain; thumbnail renders.
- [ ] A second identical event does not re-process (idempotent) — re-drop an SQS message and confirm the worker logs "skipped".
- [ ] `terraform plan` zero-diff on core / edge; app tests green.

## 5. How to tear down — reverse of provision (relative to 2b)
```bash
# The SQS queue + EventBridge rule + notification are owned by core, so they are
# destroyed by the normal env/dev destroy. The worker is a Helm release: uninstall
# it before destroying platform (its IRSA role).
helm uninstall transcode-worker -n $NS
# then follow the standard 2b teardown: DNS -> edge -> (helm uninstall app+ingress) -> platform -> core
```
No new orphan classes beyond 2b — but empty the `transcoded` bucket if a destroy complains (it has `force_destroy = true`, so this is usually automatic).

## 6. Common issues & troubleshooting
| Symptom | Root cause | Fix |
|---|---|---|
| Upload done but nothing transcodes | EventBridge not enabled on raw bucket, or rule pattern wrong | Confirm `aws_s3_bucket_notification.eventbridge=true`; check the rule matches `Object Created` + prefix `raw/`; look for messages in the queue (`aws sqs get-queue-attributes ... ApproximateNumberOfMessages`) |
| Worker pod `AccessDenied` on SQS/S3/DynamoDB | IRSA role/trust wrong or SA annotation missing | Confirm SA has `eks.amazonaws.com/role-arn`; check the `transcode-worker` policy statements |
| Same video processed twice | idempotency guard missing/incorrect | Guard must be `status IN (uploaded, failed)`; duplicates should log "skipped" |
| Messages pile up / land in DLQ | ffmpeg failing (bad input, OOM) or transcode > visibility timeout | Read worker logs; check pod memory limits; confirm `visibility_timeout_seconds` (900) exceeds transcode time |
| HLS 403 through CloudFront | transcoded bucket policy condition key typo (`AWS: SourceArn` with a space) or missing OAC | Condition key must be exactly `AWS:SourceArn`; confirm the `s3-transcoded` OAC + bucket policy |
| HLS 404 through CloudFront | behavior path ≠ real S3 key prefix | Behaviors must be `/hls/*` + `/thumbs/*` (CloudFront does not strip the prefix); worker writes keys `hls/<id>/…`, `thumbs/<id>.jpg` |
| Player shows nothing, playback returns 409 | video not `ready` yet | Expected while transcoding; retry after the worker finishes |

## 7. CV milestone achieved
An event-driven, self-hosted transcode pipeline on EKS: upload → EventBridge → SQS(+DLQ) → an idempotent FFmpeg worker → multi-bitrate HLS + thumbnail served through CloudFront → adaptive-bitrate playback on the custom domain. (Autoscale-to-zero + spot resilience + chaos come in slice 3b.)
