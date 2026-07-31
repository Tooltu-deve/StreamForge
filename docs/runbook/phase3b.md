# Runbook — Phase 3b: Autoscale & Resilience

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it. Builds on `phase3a.md` — only the 3b autoscaling/resilience pieces are covered here.

## 1. Phase objective
Make the transcode worker **scale to zero when idle and out on demand**, run on **spot**, and **lose no job** on interruption. Two layers: **KEDA** scales worker pods by SQS depth (0↔N); **Cluster Autoscaler** scales the spot node group by `Pending` pods (0↔N).

## 2. Prerequisites
- Phase 3a deployed/working (core + platform + edge + services + worker). See `phase3a.md`.
- Same shared env:
  ```bash
  export REGION=ap-southeast-1 ACCOUNT=252773257724
  export ECR=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/streamforge-dev
  export NS=streamforge
  ```
- **Verify chart versions before apply** (defaults in `platform/dev/variables.tf` may be stale):
  ```bash
  helm repo add autoscaler https://kubernetes.github.io/autoscaler
  helm repo add kedacore  https://kedacore.github.io/charts
  helm repo update
  helm search repo autoscaler/cluster-autoscaler --versions | head
  helm search repo kedacore/keda --versions | head
  ```
  Set `ca_chart_version` / `keda_chart_version` to a published version if the defaults are not found.

## 3. How to provision (Deploy) — additive to 3a
```bash
# 1. Core — adds the spot node group cluster-autoscaler discovery tags
terraform -chdir=infra/env/dev apply

# 2. Platform — installs Cluster Autoscaler (kube-system) + KEDA (keda ns), both with IRSA
terraform -chdir=infra/platform/dev apply
kubectl -n kube-system get deploy cluster-autoscaler     # Available
kubectl -n keda get deploy keda-operator                 # Available (CRDs registered)

# 3. Redeploy the worker with KEDA + spot scheduling enabled
QUEUE=$(terraform -chdir=infra/env/dev output -raw queue_url)
RAW=$(terraform -chdir=infra/env/dev output -json bucket_names | jq -r .raw)
TRANSCODED=$(terraform -chdir=infra/env/dev output -json bucket_names | jq -r .transcoded)
TABLE=$(terraform -chdir=infra/env/dev output -raw table_name)
R_W=$(terraform -chdir=infra/platform/dev output -json svc_role_arns | jq -r '."transcode-worker"')
helm upgrade --install transcode-worker charts/worker -n $NS \
  -f charts/values/transcode-worker.yaml \
  --set name=transcode-worker --set image.repo=$ECR/transcode-worker --set image.tag=$TAG \
  --set serviceAccount.roleArn=$R_W \
  --set env.REGION=$REGION --set env.RAW_BUCKET=$RAW --set env.TRANSCODED_BUCKET=$TRANSCODED \
  --set env.TABLE_NAME=$TABLE --set env.QUEUE_URL=$QUEUE --set keda.queueUrl=$QUEUE
```
> KEDA must be installed (step 2) **before** the worker chart, or `helm upgrade` fails with `no matches for kind "ScaledObject"` (the CRD won't exist yet). The `charts/values/transcode-worker.yaml` file sets `keda.enabled=true`, the spot toleration, and nodeSelector.

## 4. How to verify (DoD)
**Scale-to-zero (idle):** with an empty queue, after KEDA's cooldown:
```bash
kubectl get pods -n $NS -l app=transcode-worker    # expect: none (0 replicas)
kubectl get nodes -l workload=transcode            # expect: none (0 spot nodes)
```
**Scale-out (on upload):** upload a short video, then watch:
```bash
kubectl get pods -n $NS -w    # worker 0 -> 1 (Pending -> Running once the node is up)
kubectl get nodes -w          # a spot node appears (Cluster Autoscaler)
```
Confirm `status=ready`, then both return to 0 after the idle window.

Checklist:
- [ ] Idle → 0 worker pods AND 0 spot nodes.
- [ ] Upload → KEDA scales the worker up, CA adds a spot node, transcode completes, both scale back to 0.
- [ ] Chaos (§5) → job still reaches `status=ready`.
- [ ] DLQ (§6) → poison message lands in the DLQ after 3 attempts.
- [ ] Load (§7) → burst scales out then back to zero.
- [ ] `terraform plan` zero-diff (core/platform).

## 5. Chaos test — kill the worker mid-job
```bash
# Upload a video; while it is transcoding:
kubectl get pods -n $NS -l app=transcode-worker
kubectl delete pod -n $NS <worker-pod>      # kill it mid-transcode
```
Expected: the in-flight SQS message is NOT deleted → it reappears after the visibility timeout →
a fresh worker pod reprocesses it → `status=ready`, output intact (deterministic keys + the ADR-0008
idempotency guard mean the re-run is safe, no corruption, no manual repair).
> The requeue waits up to `visibility_timeout_seconds` (900s). For a faster demo, lower that var in
> `env/dev` and re-apply, or use a very short clip.

## 6. DLQ test — poison message
Send a message that always fails (e.g. an EventBridge-shaped body pointing at a `raw/` key that
isn't a valid video, or delete the raw object so the worker's download fails):
```bash
aws sqs send-message --region $REGION --queue-url $QUEUE \
  --message-body '{"detail":{"object":{"key":"raw/does-not-exist"}}}'
```
Expected: the worker fails, does not delete the message, SQS redelivers up to `maxReceiveCount=3`,
then moves it to the DLQ. Verify:
```bash
aws sqs get-queue-attributes --region $REGION \
  --queue-url $(terraform -chdir=infra/env/dev output -raw dlq_url) \
  --attribute-names ApproximateNumberOfMessages
```
Expect `ApproximateNumberOfMessages = 1`.

## 7. Load test — scale out then to zero
```bash
# Upload ~10 short videos quickly (via the UI, or loop presigned PUTs), then:
kubectl get pods -n $NS -w     # replicas rise toward maxReplicaCount (4)
kubectl get nodes -w           # Cluster Autoscaler adds spot nodes
```
After the queue drains and the idle window passes, confirm workers → 0 and spot nodes → 0. Save
evidence (screens/logs) to `docs/evidence/`.

## 8. Teardown note
Standard 3a order still applies — `platform/dev destroy` removes Cluster Autoscaler + KEDA (and their
IRSA) along with the ALB controller before core. The spot node group + SQS + EventBridge belong to
core and are destroyed by `env/dev destroy`. `helm uninstall transcode-worker -n streamforge` before
destroying platform.

## 9. Common issues & troubleshooting
| Symptom | Root cause | Fix |
|---|---|---|
| Worker pod stuck `Pending`, no node appears | CA not discovering the spot NG, or IRSA wrong | Confirm the spot NG discovery tags; `kubectl -n kube-system logs deploy/cluster-autoscaler` for ASG discovery / AccessDenied |
| `helm upgrade` worker: `no matches for kind "ScaledObject"` | KEDA not installed yet | Apply `platform/dev` (KEDA CRDs) before deploying the worker |
| Worker never scales up on upload | KEDA can't read queue depth | KEDA operator IRSA needs `sqs:GetQueueAttributes`; `identityOwner: operator` on the trigger; check `kubectl -n keda logs deploy/keda-operator` |
| Worker scheduled on on-demand (not spot) | Missing nodeSelector/toleration | Confirm `nodeSelector: workload=transcode` + toleration `dedicated=transcode:NoSchedule` rendered |
| Node not scaling back to 0 | Pods still on it, or CA cool-down | A running transcode blocks removal (expected); otherwise wait `scale-down-unneeded-time` (~10m) |
| Chaos test seems to lose the job | Waiting on the 900s visibility window | Expected latency; lower `visibility_timeout_seconds` for the demo or wait |

## 10. CV milestone achieved
Event-driven **scale-to-zero** for a bursty spot workload: KEDA scales the transcode worker pods by
SQS depth and Cluster Autoscaler scales the spot node group behind it — idle cost drops to ~zero,
uploads scale compute out on demand, and killed workers lose no job (SQS + idempotency). Autoscaling,
spot, and chaos/DLQ resilience demonstrated end-to-end.
