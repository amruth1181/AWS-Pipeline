# PROGRESS

Claude Code updates this after every task: tick the box, add the date and one line of notes
(what was built, anything surprising, links to PR/commit). Task details are in `docs/IMPLEMENTATION.md`.

**Current phase:** 0
**Current spend (from `make cost`):** $0.00 (as of —)
**Budget:** AWS Free plan, $100 credits, expires 2027-04-15. Showcase mode: off.

## Phase 0 — Account and local setup
- [ ] P0.1 AWS account hardening
- [ ] P0.2 Billing guardrails
- [x] P0.3 Local tools installed (2026-10-14)
- [ ] P0.4 CLI profile `urbanmove`
- [ ] P0.5 Terraform bootstrap (state bucket, budget, GitHub OIDC roles)

## Phase 1 — Repo foundations
- [ ] P1.1 Scaffold, Makefile, pre-commit
- [ ] P1.2 Shared models
- [ ] P1.3 GBFS fixtures + parser tests
- [ ] P1.4 CI (no AWS)

## Phase 2 — Ingestion, serving state and data lake (free path)
- [ ] P2.1 envs/dev root
- [ ] P2.2 storage module
- [ ] P2.3 DynamoDB tables (provisioned, Streams)
- [ ] P2.4 ingest_velib logic (sinks + raw archive)
- [ ] P2.5 ingester deployed
- [ ] P2.6 Glue + Athena

## Phase 3 — Alerts and the showcase stream
- [ ] P3.1 alert_processor logic
- [ ] P3.2 alert_processor deployed
- [ ] P3.3 showcase streaming module (Kinesis, Firehose, station_writer)
- [ ] P3.4 tests

## Phase 4 — API and auth, then ECS showcase
- [ ] P4.1 FastAPI app (local, Lambda + container entry points)
- [ ] P4.2 auth module (Cognito)
- [ ] P4.3 api module (Lambda + HTTP API) + smoke test
- [ ] P4.4 network module (showcase)
- [ ] P4.5 ecs_api module (showcase) + smoke test on both backends

## Phase 5 — Observability
- [ ] P5.1 dashboard
- [ ] P5.2 alarms
- [ ] P5.3 tracing
- [ ] P5.4 cost report

## Phase 6 — CI/CD
- [ ] P6.1 plan workflow
- [ ] P6.2 deploy workflow
- [ ] P6.3 least-privilege deploy role

## Phase 7 — Web map
- [ ] P7.1 dashboard app
- [ ] P7.2 frontend module

## Phase 8 — Traffic analytics
- [ ] P8.1 source exploration
- [ ] P8.2 batch_traffic Lambda
- [ ] P8.3 hotspots endpoint + map layer

## Phase 9 — Scalability, resilience, DR
- [ ] P9.1 stream load test
- [ ] P9.2 API load test
- [ ] P9.3 DR configuration
- [ ] P9.4 DR drill + runbook
- [ ] P9.5 security hardening + SECURITY.md

## Phase 10 — ML forecast (stretch)
- [ ] P10.1 dataset
- [ ] P10.2 model vs baselines
- [ ] P10.3 serving

## Phase 11 — Portfolio packaging
- [ ] P11.1 architecture diagram
- [ ] P11.2 README
- [ ] P11.3 REPORT.md
- [ ] P11.4 demo
- [ ] P11.5 CV + LinkedIn blurbs
- [ ] P11.6 final teardown check

## Log
<!-- YYYY-MM-DD · task id · note -->
- 2026-10-14 · plan · Switched to the hybrid free/showcase design, ARM64, Free-plan budget (ADR-008 to ADR-013).
- 2026-10-14 · P0.3 · aws-cli 2.38.0, Terraform 1.16.6, Docker 29.2.1 (daemon to be started before Phase 4), uv 0.11.5 + Python 3.12.13, git 2.52, GNU Make 3.81.
