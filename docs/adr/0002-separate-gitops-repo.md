# ADR-0002: Using separate gitops repository


- **Date:** 2026-07-13
- **Phase:** Phase 0


## Context
We need to decide how to organize the Gitops repository. The constraint is to avoid CI committing tag into the same repo, which makes it easy for infinite loop and messy history.

## Options considered
1. **Option A** — Mono-repo
2. **Option B** — Separate repo for gitops


## Decision
I chose **Option B** because it helps with better audit, permission management and more straight-forward workflow. 

## Consequences
- Positive: Better control and isolation 
- Trade-offs / risks: Need to manage 2 repos at the same time
- Follow-up work this entails: Create repo config

## References
- Links to design doc / related docs / PRs.
