# ADR-0011: Tier authorization + CloudFront signed cookies


- **Date:** 2026-08-06
- **Phase:** Phase 5 (scoped to slice 5a)


## Context

Premium video content must be watchable only by premium users, and must not be publicly
fetchable at all. Until now HLS is served publicly through CloudFront (OAC → S3): playback only
gates the *handout* of the URL, but anyone with the URL can fetch the content — security theater.
We also need a place for the signing secret that keeps it out of Terraform state and out of the
public GitOps config repo.

The original Phase 5 also included a payОС payment flow; that is **dropped** (YAGNI — high
complexity, low platform-skill payoff; idempotency/async already shown in Phase 3). A user becomes
premium via a manual `admin-add-user-to-group`.

## Options considered

1. **Content protection — tier-check only vs signed URL vs signed cookie**
   - *Tier-check only* (playback returns URL if authorized): content stays public → useless once a URL leaks.
   - *Signed URL:* must sign every segment/playlist URL — HLS has many `.ts` files → impractical.
   - *Signed cookie:* one cookie (custom policy) covers a whole path prefix → fits HLS.

2. **Gate scope — all HLS vs premium-only**
   - *Premium-only:* CloudFront is path-based; distinguishing premium per-video needs separate
     prefixes/behaviors → more moving parts.
   - *All HLS:* one `/hls/*` behavior with `trusted_key_groups`; authorization (who gets a cookie)
     decided in playback. Simpler at the edge, and blocks anonymous access to everything.

3. **Private key provisioning — Terraform-generated vs manual CLI**
   - *Terraform (`tls_private_key`):* fully IaC but the private key lands in TF state.
   - *Manual `openssl` + CLI:* key never enters state; public key (not secret) still goes to Terraform.

## Decision

- **Tier model:** each video carries `tier_required` (`free`|`premium`, default `free`, chosen at
  upload). playback compares it to the user's Cognito group (`cognito:groups` in the ID-token JWT);
  a premium video + non-premium user → **403**.
- **Signed cookies** on **all** `/hls/*` via a CloudFront `trusted_key_groups`. playback issues a
  **custom-policy** cookie scoped to `https://<app_domain>/hls/<videoId>/*`, TTL ~600s.
- **playback signs locally** with a private key read from **Secrets Manager via IRSA** (least
  privilege: `GetSecretValue` on one ARN). CloudFront verifies with the matching public key.
  Signing is RSA-SHA1 + PKCS1v15 (CloudFront's requirement); no call to CloudFront to create the cookie.
- **Key provisioning:** manual `openssl` key-pair. Public key → `aws_cloudfront_public_key` +
  `aws_cloudfront_key_group` (Terraform). Private key + `key_pair_id` → a single Secrets Manager
  secret as JSON `{key_pair_id, private_key}`, put via CLI (**never in TF state, never in the public
  GitOps repo**). The secret is created empty by Terraform; playback reads the JSON at runtime.
- **Frontend:** same-origin (`app_domain` via CloudFront), so the cookie set by the playback
  response is auto-sent on segment fetches (`hls.js` `xhrSetup` → `withCredentials`). On a 403
  (expired cookie), the Player re-calls playback for a fresh cookie and resumes (`startLoad`).
- **Premium upgrade:** manual `aws cognito-idp admin-add-user-to-group --group-name premium`.

## Consequences

- Positive: premium content is genuinely protected (no anonymous access to any HLS); the security
  building blocks (tier authz, signed cookies, Secrets-Manager-via-IRSA) are demonstrated; the
  private key never touches TF state or the public repo.
- Trade-offs / risks: even free videos need a cookie (one extra playback round-trip — fine, playback
  issues it freely); short cookie TTL means periodic refresh (handled by the FE 403 flow); the manual
  `put-secret-value` step must be re-run whenever the CloudFront public key is recreated (the
  `key_pair_id` changes). Documented in the runbook.
- Follow-up: Phase 6 replaces the direct Secrets-Manager read with External Secrets Operator.
- Dropped: payОС / membership service / webhook / circuit breaker.

## References
- Design spec: `docs/superpowers/specs/2026-08-05-streamforge-phase5-design.md`
- Plan: `docs/superpowers/plans/2026-08-05-streamforge-phase5a.md`
- Runbook: `docs/runbook/phase5.md`
- ADR-0002 (secrets never in the public config repo); Phase 4 memory (signed-URL vs cookie context).
