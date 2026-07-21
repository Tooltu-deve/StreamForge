# ADR-0005: DynamoDB Single-Table Key Schema


- **Date:** 2026-07-19
- **Phase:** Phase 1


## Context
StreamForge needs to store video metadata (title, status, tier, upload time) and serve it back to the catalog/playback/membership services. Constraints: low latency, cost that drops to zero when idle (dev is ephemeral), clean Terraform teardown, and enough query flexibility to grow without a migration.

The design must be driven by **access patterns first** (DynamoDB has no JOIN and no cheap ad-hoc `WHERE`, so every query must resolve to a `GetItem` or a `Query` on a known key — never a `Scan`):

| # | Access pattern | Served by |
|---|----------------|-----------|
| P1 | Get one video by id | Base table `GetItem(PK, SK)` |
| P2 | List videos by status (e.g. `ready`) | GSI1 `Query(GSI1PK)` |
| P3 | List most-recent videos | GSI1 (sort on `GSI1SK`, read descending) |
| P4 | Read the access tier a video requires (free/premium) | Plain attribute on the item (no index) |

## Options considered
1. **Option A — Single DynamoDB table + GSI1.** Pros: serverless, `PAY_PER_REQUEST` → $0 at rest; one resource to provision/destroy/IAM; related items co-located in one partition (item collection) so future entities (comments, chapters) join with no migration. Cons: keys must be designed up front; no ad-hoc SQL-style queries; a single table mixes item types so it reads less obviously.
2. **Option B — Multi-table RDS (relational).** Pros: familiar SQL, flexible ad-hoc queries, JOINs. Cons: an instance bills 24/7 even when idle (breaks the zero-cost-at-rest goal), needs VPC/patching/backup management, slower to tear down cleanly.
3. **Option C — Multi-table DynamoDB (one table per entity).** Pros: each table has a simple, single-purpose schema. Cons: no JOIN across tables → the app must issue N calls and stitch results client-side; more resources to provision, tag, IAM-scope, and destroy; no item-collection locality.

## Decision
I chose **Option A**. It is the only option that hits **$0 at rest** via `PAY_PER_REQUEST` while staying a single, clean resource to `apply`/`destroy` — matching the phase DoD. Over Option B it avoids an always-on billed instance and VPC/patching overhead. Over Option C — both are DynamoDB and equally durable (3-AZ replication), so durability is *not* the deciding factor; single-table wins because DynamoDB has no JOIN, and co-locating related items in one partition lets a single `Query` return a video plus its future comments/chapters, whereas multi-table would need several round-trips stitched in the application. It also stays flexible: new access patterns are new key prefixes or a new GSI, never a schema migration.

Key schema:
```
Base table:  PK = "VIDEO#<id>"          SK = "METADATA"
GSI1:        GSI1PK = "STATUS#<status>" GSI1SK = "<uploaded_at ISO-8601>"
```
- **P1** → `GetItem(PK="VIDEO#<id>", SK="METADATA")`.
- **P2** → `Query(GSI1PK="STATUS#ready")`.
- **P3** → same GSI1 query read descending on `GSI1SK` with a `Limit`; the ISO-8601 sort key sorts lexicographically == chronologically, so "recent" is free.
- **P4** → `tier` is a plain attribute returned by P1; it is not a key, so it is not declared in Terraform (only the four key attributes `PK`, `SK`, `GSI1PK`, `GSI1SK` are).

Billing is `PAY_PER_REQUEST`; PITR is intentionally disabled (dev is ephemeral, no cost).

## Consequences
- Positive: serverless, zero cost when idle, single resource that applies/destroys cleanly, flexible querying via key overloading + GSI1.
- Trade-offs / risks: keys must be designed up front (no ad-hoc queries); GSI1 is **eventually consistent** (a read right after a write may return stale data); each extra GSI adds storage and **write amplification** (every write is copied into every GSI), so new GSIs are added deliberately, not by default.
- Follow-up: PITR is off for dev — enable it for any production table. If a future pattern needs "list a specific user's videos", that is a second dimension on the same item and would require a new GSI2 (or duplicated items), not overloading GSI1.

## References
- Design spec §3.4 and §6: [../superpowers/specs/2026-07-16-streamforge-phase1-design.md](../superpowers/specs/2026-07-16-streamforge-phase1-design.md)
- Implementation: `infra/modules/dynamodb/main.tf`
