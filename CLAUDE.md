# CLAUDE.md — UrbanMove

Context for Claude Code. Read this first in every session, then `docs/IMPLEMENTATION.md` and `docs/PROGRESS.md`.

## What this project is

**UrbanMove** is a real-time smart-mobility platform for Paris, built cloud-native on AWS.
It ingests **live Vélib' bike-share data** (GBFS, refreshed every minute) and **Paris road-traffic
sensor data** (daily batch), processes it in a stream, and serves availability, congestion and
"where can I get a bike / drop a bike" recommendations through an authenticated API and a web map.

It is a **personal portfolio project** by Amruth Ganta (MSc AI Systems & Data Science, EPITA).
The goal is to show production-grade cloud data engineering: streaming, IaC, security, HA,
observability, CI/CD, cost control and disaster recovery — at a student budget.

Full spec: `docs/PROJECT_BRIEF.md` · Architecture: `docs/ARCHITECTURE.md` ·
Data sources: `docs/DATA_SOURCES.md` · Decisions: `docs/DECISIONS.md`

## How to work in this repo

1. **Follow `docs/IMPLEMENTATION.md` in order.** Work on one task at a time. Don't jump phases.
2. Before coding a task: state the plan in 3–6 bullets, list the files you'll touch, then build.
3. After a task: run the task's **Verify** steps, then tick it in `docs/PROGRESS.md` with the date and
   one line of notes. Never tick a task whose verification you didn't run.
4. Any non-obvious design choice gets a short entry in `docs/DECISIONS.md` (ADR style).
5. Keep changes small and reviewable. One task ≈ one commit. Use Conventional Commits
   (`feat(api): ...`, `infra(network): ...`, `fix(processor): ...`, `docs: ...`).
6. If a task in `docs/IMPLEMENTATION.md` turns out wrong or impossible, stop and explain. Propose
   an edit to the plan instead of silently doing something different.

## Hard guardrails (do not break)

- **Never run `terraform apply`, `terraform destroy`, or any mutating `aws` CLI command without
  asking first.** Show the `terraform plan` summary (resources to add/change/destroy and the
  estimated monthly cost impact), then wait for a yes.
- **Never commit secrets.** No keys, tokens or passwords in code, tfvars, or tests. Runtime secrets
  live in SSM Parameter Store (SecureString). `.env` is git-ignored; only `.env.example` is committed.
- **No long-lived AWS keys in CI.** GitHub Actions uses OIDC to assume an IAM role.
- **Region is `eu-west-3` (Paris).** DR copies go to `eu-west-1` (Ireland). Don't use other regions.
- **AWS CLI profile is `urbanmove`.** Always pass `--profile urbanmove` or use `AWS_PROFILE=urbanmove`.
- **Every AWS resource is tagged**: `Project=urbanmove`, `Env=<env>`, `Owner=amruth`, `ManagedBy=terraform`
  (set via `default_tags` in the provider, not by hand).
- **Cost first.** The account is on the AWS **Free plan: $100 credits, expiring 2027-04-15**; after that it needs
  the Paid plan. The always-on path must stay inside free allowances (~$0/month). Anything with an
  hourly charge (NAT gateway, ALB, interface VPC endpoints, Kinesis shards, public IPv4, WAF, KMS CMKs) belongs in
  showcase mode, must be called out in the plan with its rough monthly cost, and must be removable via a variable or
  `make down`. Watch free-tier ceilings: DynamoDB 25 RCU/WCU, CloudWatch 10 custom metrics / 10 alarms.
- **The repo path contains a space** (`aws urban`). Quote paths in shell and scripts; in the Makefile use relative paths
  only, never `$(CURDIR)` in targets or prerequisites.
- **Least privilege IAM.** One role per component, scoped to specific ARNs. No `*:*`, no `AdministratorAccess`
  on workloads. `Resource: "*"` only where AWS requires it (e.g. some `Describe*`, `xray:Put*`).
- Don't change files outside this repo.

## Tech stack

| Layer | Choice |
|---|---|
| IaC | Terraform ≥ 1.10 (S3 backend with native lockfile), AWS provider ~> 5.x |
| Language | Python 3.12 everywhere |
| Deps / tooling | `uv` for env + deps, `ruff` (lint + format), `mypy` (light), `pytest`, `moto` for AWS mocks |
| Architecture | **Hybrid** (ADR-008): free always-on path + showcase mode behind `kinesis_enabled` / `ecs_enabled` |
| Compute arch | **ARM64** everywhere (Lambda `arm64`, Fargate `ARM64`, images `linux/arm64`) — ADR-010 |
| Ingestion | EventBridge Scheduler (5 min) → Lambda poller → DynamoDB. Showcase: → Kinesis Data Streams (1 shard) |
| Stream processing | DynamoDB Streams → `alert_processor` Lambda. Showcase: Kinesis → `station_writer` Lambda |
| Raw archive | Ingester writes gzip JSONL per poll to S3 (`dt=YYYY-MM-DD/hr=HH`). Showcase: Firehose, same layout |
| Serving store | DynamoDB **provisioned within free tier** (≤ 25 RCU/WCU total), Streams on, PITR on — ADR-009 |
| Analytics | Glue Data Catalog (Terraform-defined tables, partition projection) + Athena; view `velib_events` excludes synthetic |
| API | FastAPI on Lambda (Mangum). Showcase: same app in Docker on ECS Fargate (2 AZs, autoscaling) behind an internal ALB |
| API edge | API Gateway HTTP API (HTTPS, JWT authorizer with Cognito, throttling) → Lambda, or VPC Link → ALB in showcase |
| Auth | Cognito User Pool (users) + app client for machine-to-machine (client credentials) |
| Frontend | Static Leaflet map on S3 + CloudFront (OAC) |
| Observability | CloudWatch Logs (JSON), metrics, dashboard, alarms → SNS email; AWS Budgets |
| CI/CD | GitHub Actions (lint/test, terraform plan on PR, build→ECR→ECS deploy on main) |
| Load testing | Locust (API) + Python simulator (stream) |

## Repo layout (target)

```
infra/
  bootstrap/            # one-time: tf state bucket, GitHub OIDC role, budget alarm
  modules/              # network, storage, streaming, processing, api, auth, frontend, observability, dr
  envs/dev/             # composes modules; the only root you plan/apply day to day
services/
  ingest_velib/         # Lambda: poll GBFS -> DynamoDB + S3 raw (showcase: -> Kinesis)
  alert_processor/      # Lambda: DynamoDB Streams -> alerts, freshness metric
  station_writer/       # Lambda (showcase): Kinesis -> DynamoDB
  batch_traffic/        # Lambda: daily Paris traffic sensors -> S3
  api/                  # FastAPI app: Lambda handler (Mangum) + Dockerfile (showcase ECS)
  simulator/            # synthetic load generator -> Kinesis
  common/               # shared pydantic models, logging, config
dashboard/              # static web map
ml/                     # (phase 8) availability forecasting
load/                   # locust files
scripts/                # helper scripts (smoke tests, seed users, cost report)
.github/workflows/
docs/
```

## Commands (keep the Makefile in sync with this list)

```
make setup          # uv sync, pre-commit install
make lint           # ruff check + ruff format --check + terraform fmt -check
make test           # pytest (unit, moto-mocked)
make plan           # terraform -chdir=infra/envs/dev plan
make apply          # terraform apply (asks)
make up             # showcase mode on: kinesis_enabled=true ecs_enabled=true (hourly cost!)
make down           # showcase mode off (keeps the free path and all data: S3, DynamoDB, Cognito)
make nuke           # full destroy of envs/dev (asks twice)
make build-api      # docker build services/api
make push-api       # push to ECR
make smoke          # scripts/smoke_test.sh against the deployed API
make load           # locust headless run
make cost           # scripts/cost_report.py — month-to-date spend by service
```

## Code conventions

- Python: type hints everywhere, pydantic v2 models for every event/record shape (in `services/common`).
- Structured JSON logs (`aws-lambda-powertools` Logger for Lambdas; `structlog` or std logging JSON for the API).
  Every log line carries `service`, `event_type`, and a correlation id when there is one.
- Config comes from env vars only (12-factor). No hard-coded ARNs/names in Python.
- Handlers are thin; logic lives in pure functions that are unit-tested without AWS.
- Lambdas are idempotent: processing the same poll, stream record or Kinesis record twice must not corrupt state
  (conditional writes keyed on `station_id` + `last_reported`).
- Kinesis partition key = `station_id` (ordering per station).
- Timestamps: UTC, ISO 8601 in JSON, epoch seconds in DynamoDB sort keys.
- Terraform: one module per concern, `variables.tf` / `outputs.tf` / `main.tf` / `versions.tf`,
  every variable has a description and type, no hard-coded account IDs (`data.aws_caller_identity`).
- Tests live next to code (`services/<svc>/tests`). Target ≥ 80% coverage on `services/common` and processor logic.

## Definition of done (per task)

- Code + tests written, `make lint` and `make test` pass.
- Terraform: `fmt`, `validate`, and a clean `plan` shown to the user.
- Verify steps from `docs/IMPLEMENTATION.md` executed and their output summarized.
- `docs/PROGRESS.md` updated; ADR added if a design choice was made.
- README / docs updated if behavior or commands changed.
