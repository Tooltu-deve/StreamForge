# ADR-0001: Remote Backend

- **Date:** 2026-07-13
- **Phase:** Phase 0


## Context
Problem: the need to store terraform state securely and avoid conflict when running in local and CI/CD pipeline. The solution must be secured with encryption at rest and in transit, and has lock state to prevent conflict applies.

## Options considered
1. **Option A** — Store terraform state local 
2. **Option B** — S3 backend 
3. **Option C** — Terraform Cloud

## Decision
I chose **Option B** because it offers the features that meet the requirements of secure and conflict problem. S3 backend is a method to store terraform state in a S3 bucket which has encryption at rest and in transit by default. Moreover, it also supports lockfile to avoid conflict problems. Terraform Cloud is also a good solution but S3 is a AWS solution which is easier for me to understand. 

## Consequences
- Positive: Secure terraform state both in transit and at rest, mitigate the risk of unwanted access; S3 also supports versioning which allows us to roll back the state to a healthy previous state when the newest state fails
- Trade-offs / risks: S3 bucket has to exist before migrating state to it, so we need to bootstrap with local state first and then migrate that state to S3 bucket
- Follow-up work this entails: S3 + DynamoDB is deprecated, Terraform recommended not to use it for better future compatiability

## References
- Links to design doc / related docs / PRs.
