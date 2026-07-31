# ADR-0008: Event-driven self-hosted transcode pipeline


- **Date:** 2026-07-29
- **Phase:** Phase 3 (slice 3a)


## Context

After a user uploads a raw video to the `raw` S3 bucket, the platform must transcode it into a
multi-bitrate HLS ladder so it can be watched with adaptive bitrate (ABR) over the custom domain,
plus produce a thumbnail. This is the core of Phase 3. The decisions below shape how the pipeline
is triggered, where transcoding runs, how it stays correct under at-least-once delivery, and how
the output is served.

Constraints: ephemeral/near-$0 at rest; the portfolio goal is to demonstrate DevOps/SRE skills
(autoscaling, spot, DLQ, idempotency) rather than to outsource the hard parts; keep a single public
entry (CloudFront) established in Phase 2.

## Options considered

1. **Transcode engine — self-hosted FFmpeg on EKS vs AWS MediaConvert.**
   - *MediaConvert (managed):* less operational work, but removes the entire learning surface of the
     phase (KEDA scale-to-zero, spot interruption, DLQ chaos) and bills per minute.
   - *Self-hosted FFmpeg worker on EKS spot:* more ops, but exactly the skills this project exists to
     show; ~$0 when idle via scale-to-zero (3b).

2. **Event trigger — S3→SQS direct notification vs S3→EventBridge→SQS.**
   - *Direct S3→SQS:* one hop, but couples the bucket to one consumer; adding a second reaction later
     (e.g. an instant-thumbnail Lambda) means reconfiguring bucket notifications.
   - *S3→EventBridge→SQS:* one extra hop, but a single event bus; new reactions are just new rules.

3. **Idempotency under at-least-once SQS delivery.**
   - *No guard:* a redelivered or duplicated message re-transcodes / double-processes.
   - *DynamoDB conditional update (`status IN (uploaded, failed)`) + deterministic output keys
     (`hls/<id>/…`, `thumbs/<id>.jpg`):* the first worker to flip `status→processing` wins; a duplicate
     hits `ConditionalCheckFailedException` and no-ops; re-runs overwrite the same keys safely.

4. **Rendition ladder — 4 rungs (240/480/720/1080) vs fewer.**
   - Four rungs is production-like but slower/costlier to transcode and more playlist complexity;
     for a demo it is over-built (YAGNI). Three rungs (360/720/1080) still demonstrates ABR.

5. **Thumbnail generation — separate S3-triggered Lambda vs inside the worker.**
   - A separate Lambda re-downloads the video and needs an FFmpeg layer/container.
   - The worker already has the decoded video in hand during transcode, so extracting one frame in the
     same pass is free.

6. **Serving transcoded output — presigned S3 URLs vs CloudFront behaviors.**
   - Presigned URLs bypass the single public entry and complicate premium gating later.
   - CloudFront behaviors keep one entry and set up Phase 5 signed-cookie gating cleanly. Note:
     CloudFront does **not** strip the path prefix, so behavior paths must equal the real S3 key
     prefixes (`/hls/*`, `/thumbs/*`) — an invented `/media/*` alias would 404.

## Decision

Chosen: **event-driven, self-hosted transcode**.

- **Engine:** a Python FFmpeg worker running as a pod on EKS (Deployment in 3a; KEDA-scaled in 3b).
- **Trigger:** raw-bucket `Object Created` → **EventBridge** → **SQS** main queue, with a **DLQ**
  (`maxReceiveCount = 3`) and a `900s` visibility timeout (> worst-case single-video transcode).
- **Idempotency:** DynamoDB conditional update guard `status IN (uploaded, failed)` plus deterministic
  output keys. A duplicate message is a no-op; a mid-job failure is retried and finally DLQ'd.
- **Ladder:** three rungs — **360p / 720p / 1080p**.
- **Thumbnail:** produced inside the worker (`thumbs/<id>.jpg`), stored as `thumbnail_key`.
- **Serving:** CloudFront gets a second OAC origin (the `transcoded` bucket) and two cache behaviors
  `/hls/*` + `/thumbs/*`; playback returns `https://<app_domain>/<hls_key>`. Public in 3a; signed-cookie
  gating is deferred to Phase 5.

## Consequences

- Positive: near-$0 at rest (worker scales to zero in 3b); at-least-once delivery is safe; single public
  entry preserved; adding future event reactions is a new EventBridge rule, not a bucket reconfig.
- Trade-offs / risks: self-hosting FFmpeg is more operational surface (spot drain, DLQ handling — 3b);
  the worker must keep transcode time under the SQS visibility window (idempotency covers overruns);
  large videos need bounded ephemeral storage.
- Follow-up (3b): KEDA `ScaledObject` on SQS depth + scale-to-zero; spot node group taint/toleration +
  node-termination drain; chaos test (kill worker mid-job) and a DLQ/redrive test.

## References
- Design spec: `docs/superpowers/specs/2026-07-27-streamforge-phase3a-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-28-streamforge-phase3a.md`
- Runbook: `docs/runbook/phase3a.md`
- Thumbnail decision predates this ADR (folded into the worker).
