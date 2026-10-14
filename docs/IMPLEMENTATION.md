# IMPLEMENTATION.md — UrbanMove build plan

The step-by-step plan Claude Code follows. Work **top to bottom, one task at a time**.
Each task has an ID (e.g. `P2.3`), what to build, and how to **Verify** it. Track status in `docs/PROGRESS.md`.

> Rule of thumb: nothing is "done" until its Verify step was actually run and passed.

---

## 0. Big picture

**Hybrid design (ADR-008).** An always-on **free path** that fits the AWS free allowances, plus a **showcase mode**
(Kinesis, Firehose, ECS Fargate, ALB) switched on only for load tests, screenshots and demos.

```
                         ┌──────────────────────────── eu-west-3 (Paris) ───────────────────────────────┐
 Vélib' GBFS ──────────► │ EventBridge Scheduler ─► Lambda ingest_velib ─┬─► DynamoDB stations          │
                         │   (every 5 min)       (diff vs S3 snapshot)   │      │ DynamoDB Streams      │
                         │                                               │      ▼                       │
                         │                                               │  Lambda alert_processor      │
                         │                                               │  (OLD vs NEW image → alerts) │
                         │                                               └─► S3 raw/velib/ (gzip JSONL) │
                         │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ showcase: kinesis_enabled ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
 Simulator (load) ─────► │ ingest_velib ─► Kinesis (1 shard) ─┬─► Lambda station_writer ─► DynamoDB     │
                         │                                    └─► Firehose ─► S3 raw/velib/            │
                         │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
 Paris traffic sensors ─►│ EventBridge (daily) ─► Lambda batch_traffic ─► S3 raw/ curated/              │
   (daily, D-1)          │                                   Glue Catalog + Athena                      │
                         │                                                                              │
 Users / services ─HTTPS─► API Gateway HTTP API (Cognito JWT authorizer, throttling)                    │
   (JWT from Cognito)    │   ├─ default:  Lambda api (FastAPI + Mangum, ARM64)                          │
                         │   └─ showcase: ecs_enabled → VPC Link ─► internal ALB ─► ECS Fargate (2 AZs) │
 Browser ───────────────►│ CloudFront ─► S3 (Leaflet web map) ── calls API with Cognito token           │
                         │ CloudWatch: logs, metrics, dashboard, alarms ─► SNS email · AWS Budgets       │
                         └──────── S3 CRR (raw/) ─► eu-west-1 DR bucket ────────────────────────────────┘
 GitHub Actions ──OIDC──► IAM deploy role ─► Lambda / ECR / ECS / Terraform
```

Details and justifications: `docs/ARCHITECTURE.md`.

### Budget context

AWS **Free plan**: $100 credits, expiring **2027-04-15** (183 days from 2026-10-14). Up to $100 more can be earned via
the Billing console's onboarding activities. After expiry the account must be upgraded to the Paid plan or it closes,
so the always-on path must stay near **$0/month**. All compute is **ARM64** (Graviton, ADR-010).

### Cost switches (Terraform variables in `infra/envs/dev`)

| Variable | Default | What it controls | Rough cost when on |
|---|---|---|---|
| `ingest_enabled` | `true` | Scheduler + ingester (free path) | ~$0 (free tier) |
| `kinesis_enabled` | `false` | **Showcase.** Kinesis stream, Firehose, `station_writer` mapping; ingester sinks to Kinesis | ~$0.45/day |
| `ecs_enabled` | `false` | **Showcase.** VPC, ALB, ECS service, VPC Link; HTTP API routes to ALB instead of Lambda | ~$1.5–2/day (ALB + 2 ARM tasks + 2 public IPv4) |
| `network_mode` | `"cost"` | Only with `ecs_enabled`. `cost` = no NAT, tasks in public subnets with locked SG. `prod` = NAT GW + private subnets | NAT ≈ $1.1/day |
| `enable_crr` | `false` | Cross-region replication of `raw/` to eu-west-1 | cents |
| `enable_flow_logs` | `false` | VPC flow logs → CloudWatch (7-day retention) | cents |

`make up` = `kinesis_enabled=true ecs_enabled=true`. `make down` = both `false` (keeps data, Cognito, DynamoDB, S3,
and the free path). Prices are rough eu-west-3 figures; check the AWS Pricing Calculator before relying on them.

**Free-tier limits to respect in design:** DynamoDB provisioned capacity (25 RCU / 25 WCU total, account-wide),
CloudWatch (10 custom metrics, 10 alarms, 3 dashboards), Lambda (1M requests, 400k GB-s per month).

**Start ingestion early (Phase 2).** Phases 8 and 10 need weeks of history in S3. The free path costs ~$0,
so leave it running.

---

## Phase 0 — Account and local setup (manual, ~1 hour)

These steps are for **Amruth**, not Claude Code. Claude can guide but must not create accounts or credentials.

- [ ] **P0.1 AWS account hardening.** Root MFA on, no root access keys. Create an admin identity
  (IAM Identity Center user, or an IAM user with MFA) for daily work.
- [ ] **P0.2 Billing guardrails.** Enable *Receive Billing Alerts*, Cost Explorer, and Free Tier usage alerts.
  (The Terraform budget in P0.5 is the main guardrail.)
- [ ] **P0.3 Local tools.** Install and check versions:
  `aws --version` (v2), `terraform -version` (≥ 1.10), `docker --version`, `uv --version`, `git`, `make`.
  On Windows, use WSL2 Ubuntu for all of this.
- [ ] **P0.4 CLI profile.** `aws configure sso --profile urbanmove` (or `aws configure --profile urbanmove`),
  region `eu-west-3`. Verify: `aws sts get-caller-identity --profile urbanmove`.
- [ ] **P0.5 Bootstrap Terraform** (`infra/bootstrap/`, Claude writes it, Amruth applies it once):
  - S3 bucket `urbanmove-tfstate-<account_id>`: versioning, SSE-S3, public access blocked, TLS-only bucket policy.
  - AWS Budgets (USD): monthly cost budget **$10**, credits **excluded** (so it tracks real usage, not the net bill),
    email alerts at 50%, 80%, 100% actual and 100% forecasted. Setting up a budget also earns a Free-plan credit.
  - GitHub OIDC provider + two IAM roles: `urbanmove-gha-plan` (read-only plus state access) and
    `urbanmove-gha-deploy` (scoped deploy permissions). Trust is limited to repo `amruth1181/AWS-Pipeline`:
    plan role for `pull_request`, deploy role only for the `dev` environment.
  - Bootstrap state stays **local** (`infra/bootstrap/terraform.tfstate`, git-ignored). Document this in an ADR.
  - **Verify:** `terraform -chdir=infra/bootstrap plan` shows only these resources. After apply,
    the budget appears in the console and the alert email confirmation arrives.

---

## Phase 1 — Repo foundations (no AWS spend)

- [ ] **P1.1 Scaffold.** Create the layout from `CLAUDE.md`, `pyproject.toml` (uv workspace or a single project
  with optional dependency groups per service), `.pre-commit-config.yaml` (ruff, terraform_fmt, end-of-file,
  detect-private-key, gitleaks), `Makefile` with every target from `CLAUDE.md` (stub any that don't apply yet).
  **Verify:** `make setup && make lint && make test` run clean on the empty skeleton.
- [ ] **P1.2 Shared models** in `services/common/`:
  - `StationInfo` (from `station_information.json`), `StationStatus` (from `station_status.json`)
  - `StationChangedEvent` (the Kinesis payload): `event_type`, `event_id` (uuid), `station_id`, `stationCode`,
    `num_bikes_available`, `mechanical`, `ebike`, `num_docks_available`, `is_installed`, `is_renting`,
    `is_returning`, `last_reported`, `ingested_at`, `source="velib"`, `synthetic: bool`
  - `Alert` (`station_id`, `ts`, `kind` ∈ {`became_empty`,`became_full`,`out_of_service`,`back_in_service`})
  - JSON logging helper and env-var config loader.
  **Verify:** unit tests, including round-trip (de)serialization and rejection of malformed payloads.
- [ ] **P1.3 GBFS fixtures.** Script `scripts/fetch_gbfs_fixture.py` downloads live `station_information.json`
  and `station_status.json` once and saves a **trimmed** copy (about 20 stations) under
  `services/common/tests/fixtures/`. Parsers are tested against them. Record the real Vélib' field names
  (e.g. the `num_bikes_available_types` list with `mechanical`/`ebike`, `stationCode`) in `docs/DATA_SOURCES.md`.
  **Verify:** parser tests pass on the real fixture.
- [ ] **P1.4 CI (no AWS).** `.github/workflows/ci.yml` on PR and push: uv sync, ruff, mypy, pytest with coverage,
  `terraform fmt -check -recursive`, `terraform validate` per root (with `-backend=false`), `tflint`,
  `checkov -d infra` (soft-fail at first, hard-fail from Phase 9), and a docker build of `services/api`
  once it exists.
  **Verify:** push a branch, open a PR, CI is green.

---

## Phase 2 — Ingestion, serving state and data lake (free path, ~$0)

- [ ] **P2.1 `infra/envs/dev` root.** S3 backend (`use_lockfile = true`), provider with `default_tags`,
  `region = "eu-west-3"`, plus a provider alias for `eu-west-1`. Locals for naming: `urbanmove-dev-<thing>`.
  **Verify:** `terraform init` and `plan` (empty).
- [ ] **P2.2 Module `storage`.** Data lake bucket `urbanmove-dev-lake-<account_id>`:
  - versioning on; SSE-S3; block public access; bucket policy denying non-TLS requests
  - prefixes `raw/velib/`, `raw/traffic/`, `curated/`, `state/`, `athena-results/`
  - lifecycle: `raw/` → STANDARD_IA at 30 days → GLACIER_IR at 90 days; noncurrent versions expire after 30 days;
    `athena-results/` expires after 7 days
  - Athena workgroup `urbanmove` with enforced result location and a 1 GB per-query scan limit
  **Verify:** plan and apply (ask first). `aws s3api get-bucket-encryption` and `get-public-access-block` return the expected settings.
- [ ] **P2.3 DynamoDB tables** (module `state`), **PROVISIONED** capacity inside the free tier (ADR-009), PITR on,
  SSE (AWS-owned key), deletion protection on (variable so `make nuke` can turn it off first):
  - `urbanmove-dev-stations`: PK `station_id`. Static info plus latest state, `geohash6`, `updated_at`.
    Capacity 10 RCU / 15 WCU. **DynamoDB Streams on, `NEW_AND_OLD_IMAGES`.**
  - `urbanmove-dev-alerts`: PK `station_id`, SK `ts` (epoch). TTL attribute `expires_at` (7 days). 5 RCU / 5 WCU.
  - Account-wide total must stay ≤ 25 RCU / 25 WCU. No GSIs (ADR-006).
  **Verify:** apply. `aws dynamodb describe-table` shows PROVISIONED, stream enabled, PITR on.
- [ ] **P2.4 `services/ingest_velib` Lambda logic.**
  - Fetch `station_status.json` (and `station_information.json` once per hour, saved to `state/station_information.json`)
  - Load the previous snapshot `state/last_status.json.gz` from S3. Build a `StationChangedEvent` only for stations
    whose `last_reported` **or** counts changed. Write the new snapshot back.
  - **Sink abstraction:** `DynamoSink` (default) applies changes with `apply_station_changes()`: conditional
    `UpdateItem` (`attribute_not_exists(last_reported) OR last_reported <= :new`), bounded write rate, retry on
    `ProvisionedThroughputExceededException` with backoff. `KinesisSink` (when `KINESIS_STREAM_NAME` is set, showcase)
    does `PutRecords` in batches of ≤ 500, partition key = `station_id`, retries failed records.
  - **Raw archive (free path):** one gzip JSONL object per poll to `raw/velib/dt=YYYY-MM-DD/hr=HH/<epoch>.json.gz` (UTC).
    Skipped when `KinesisSink` is active (Firehose archives instead), same layout so one Glue table covers both.
  - Emit EMF metrics: `StationsFetched`, `ChangesEmitted`, `WriteFailures`, `FetchErrors` (keep the project total
    of custom metrics ≤ 10)
  - Timeouts: HTTP 10 s, Lambda 60 s; memory 256 MB; ARM64. No reserved concurrency (ADR-013): overlap is
    impossible because the timeout (60 s) is far below the poll interval and the schedule has retries off.
  - Handle 502 and 404 from the feed gracefully (log, emit `FetchErrors`, don't crash-loop)
  **Verify:** unit tests (diff logic, conditional writes, throttling retry, Kinesis batching and partial-failure retry,
  archive key layout) with moto and the fixtures.
- [ ] **P2.5 Deploy the ingester.** Terraform: Lambda (ARM64 zip built by `uv` for `aarch64-manylinux`),
  IAM role (`dynamodb:UpdateItem` on stations, `s3:GetObject`/`PutObject` on `state/*` and `PutObject` on `raw/velib/*`;
  `kinesis:PutRecords` on the stream ARN only when `kinesis_enabled`), log group (14-day retention),
  EventBridge Scheduler `rate(5 minutes)` (variable `poll_interval_minutes`, revisit after P1.3 measures feed freshness),
  retries off, plus a failure destination (SQS DLQ).
  **Verify:** apply. Within 15 minutes the Lambda logs show fetched/changed counts, the stations table is filling, and
  `aws s3 ls s3://<lake>/raw/velib/ --recursive | head` shows objects.
- [ ] **P2.6 Glue Catalog and Athena.** Glue database `urbanmove`, table `raw_velib_events` (JSON SerDe) defined in
  Terraform with **partition projection** on `dt` and `hr`, so no crawler is needed. View `velib_events` =
  `raw_velib_events WHERE synthetic = false` (ADR-012); all analytics use the view. Saved named queries:
  latest status per station, empty-station minutes per arrondissement per day, hourly utilisation curve.
  **Verify:** run `SELECT count(*) FROM velib_events WHERE dt = <today>` in Athena; it returns > 0
  and scans only that partition.

---

## Phase 3 — Alerts and the showcase stream

- [ ] **P3.1 `services/alert_processor` logic (pure functions).**
  - Input: DynamoDB Streams records with OLD and NEW images of a station (ADR-009, this is where the previous state
    comes from).
  - Compute the transition (became empty / became full / out of service / back in service) and build `Alert`s.
  - Ignore records where nothing alert-relevant changed. Compute `DataFreshnessSeconds = now - max(last_reported)` per batch.
- [ ] **P3.2 Alert processor deploy.** DynamoDB Streams event source mapping: batch size 100, batching window 5 s,
  `bisect_batch_on_function_error`, max retries 3, on-failure destination SQS DLQ, `ReportBatchItemFailures`.
  IAM: read the stations stream, `PutItem` on alerts, metrics via EMF only. ARM64. Log retention 14 days.
  Seed static station info (name, lat/lon, capacity) from `state/station_information.json` with a small hourly job
  or inside the ingester. Pick one and record the choice in an ADR.
  **Verify:** apply. `aws dynamodb scan --select COUNT` on stations ≈ the number of Vélib' stations.
  Alerts appear over time. The `DataFreshnessSeconds` metric shows in CloudWatch.
- [ ] **P3.3 Showcase streaming module** (module `streaming`, everything gated by `kinesis_enabled`, default off):
  - Kinesis Data Stream `urbanmove-dev-events`: PROVISIONED, 1 shard, 24 h retention, SSE with `alias/aws/kinesis`
  - Firehose `urbanmove-dev-raw-velib`: source = the stream; destination = S3 `raw/velib/dt=!{timestamp:yyyy-MM-dd}/hr=!{timestamp:HH}/`;
    GZIP; buffer 5 MB / 300 s; error prefix `raw/_errors/`; its own least-privilege IAM role
  - `services/station_writer` Lambda (Kinesis ESM, batch 500, window 5 s, bisect, DLQ, `ReportBatchItemFailures`):
    validates events, drops and counts `synthetic=true`, and calls the same `apply_station_changes()` as the ingester.
  - When on, the ingester gets `KINESIS_STREAM_NAME` and switches to `KinesisSink`. The alert processor is unchanged.
  **Verify:** `make up-stream` (or `kinesis_enabled=true`) → `describe-stream-summary` ACTIVE, stations keep updating,
  Firehose objects appear under `raw/velib/` → switch off → the ingester is back on `DynamoSink` with no gap.
- [ ] **P3.4 Tests.** Unit tests for transitions, idempotency and the sink switch. Integration tests with moto:
  (a) ingester → DynamoDB including a replayed duplicate poll, (b) Kinesis event → `station_writer` → DynamoDB
  including a replayed duplicate batch, (c) stream record → alert processor → alerts table.

---

## Phase 4 — API and auth (free path), then ECS showcase (hourly costs only when `ecs_enabled=true`)

- [ ] **P4.1 FastAPI app (local first)** in `services/api`:
  - `GET /v1/health` (no auth): status, version, git sha, backend (`lambda` or `ecs`)
  - `GET /v1/stations?bbox=` and `GET /v1/stations/{id}`
  - `GET /v1/stations/nearby?lat=&lon=&radius_m=&need=bike|ebike|dock&limit=`
  - `GET /v1/recommend/trip?from_lat=&from_lon=&to_lat=&to_lon=`: best pickup station near the origin with
    bikes, best drop station near the destination with docks. Score = walking distance (haversine) plus a
    reliability penalty when the count is below 2. Return the walking distance and a straight-line ride estimate.
  - `GET /v1/alerts?since=` (**operators only**: requires the `operators` group in the `cognito:groups` claim)
  - `GET /v1/traffic/hotspots?date=` (Phase 8; returns 501 until then)
  - Station cache: in-memory, refreshed every 30 s (configurable). Source decided in this task: DynamoDB Scan
    (~60 RCU per refresh, tight against provisioned capacity) or the S3 snapshot the ingester already writes. ADR-006 update.
  - Pydantic response models, OpenAPI docs at `/docs` (disabled in prod via an env flag), JSON logs, request-id middleware
  - Auth (defence in depth): API Gateway already validates the JWT, and the API **re-validates** the `Authorization`
    bearer token against the Cognito JWKS (cached, using `python-jose` or `pyjwt`), checking issuer, expiry, `token_use`,
    and client id. Authorization checks (groups, scopes) live in one FastAPI dependency. **Locally**, a `DEV_AUTH_BYPASS=1` flag injects fake claims. It must never be set in AWS.
  - Two entry points, same app: `handler.py` (Mangum, for Lambda) and the Dockerfile (for ECS showcase):
    multi-stage, `python:3.12-slim`, `linux/arm64`, non-root user, `uvicorn` with 2 workers, a HEALTHCHECK, image < 200 MB
  - `docker-compose.yml` with DynamoDB Local plus a seed script for local development
  **Verify:** `make test` (endpoint tests with moto or DynamoDB Local), `docker compose up`, then curl each endpoint.
- [ ] **P4.2 Module `auth`.** Cognito User Pool: email sign-in, strong password policy, MFA optional (TOTP),
  cheapest feature plan that supports what we need (check current Lite/Essentials pricing first). Group `operators`.
  App clients: `web` (public, auth code + PKCE, callback = CloudFront URL and `http://localhost:5173`) and
  `service` (confidential, client-credentials, resource-server scope `urbanmove/read`). **Check M2M pricing before
  creating `service`; skip it and note it in an ADR if it is not free.**
  Managed login domain prefix `urbanmove-<suffix>`. `scripts/create_user.sh` creates a test user and an operator user.
- [ ] **P4.3 Module `api` (free path).** Lambda `urbanmove-dev-api` (ARM64, 512 MB, Mangum handler, task role =
  read stations / Query alerts / read S3 snapshot as decided in P4.1). API Gateway HTTP API with Lambda proxy integration.
  JWT authorizer (issuer = user pool, audience = the client ids). Routes: `GET /v1/health` with no auth,
  `ANY /v1/{proxy+}` with JWT. Stage throttling 50 rps, burst 100. Access logs as JSON to CloudWatch (14 days).
  CORS for the CloudFront origin and localhost.
  **Verify:** `scripts/smoke_test.sh`: health is 200 with no token; `/v1/stations` is 401 with no token and 200 with
  a user token; `/v1/alerts` is 403 for a normal user and 200 for an operator; a client-credentials token works on
  `/v1/stations` (if the M2M client exists).
- [ ] **P4.4 Module `network` (showcase, gated by `ecs_enabled`).** VPC `10.20.0.0/16`, 2 AZs (`eu-west-3a`, `eu-west-3b`),
  public `/24` ×2, private `/24` ×2, IGW, route tables, **S3 and DynamoDB gateway endpoints** (free).
  `network_mode="prod"` adds a NAT GW (one shared; a variable allows one per AZ). Security groups:
  `sg-alb` (ingress 80 from the VPC Link SG only), `sg-api-task` (ingress 8000 from `sg-alb` only), egress 443.
  Optional flow logs. **Verify:** plan shows no NAT in `cost` mode.
- [ ] **P4.5 Module `ecs_api` (showcase, gated by `ecs_enabled`).** ECR repo (scan on push, immutable tags, lifecycle
  keeps the last 5). ECS cluster (Container Insights off by default), task definition (ARM64, 0.25 vCPU / 0.5 GB,
  awslogs driver, read-only root FS, same task permissions as the Lambda API), service (desired 2, spread across AZs,
  deployment circuit breaker with rollback, health check grace), **internal ALB** (HTTP 80 inside the VPC, health
  check `/v1/health`). Autoscaling: target tracking on CPU 60% **and** `ALBRequestCountPerTarget` 200; min 1, max 4.
  In `cost` mode tasks run in public subnets with `assign_public_ip=true` (needed to reach ECR with no NAT),
  but `sg-api-task` only accepts traffic from the ALB (ADR-003). VPC Link (private subnets, its own SG) → ALB listener;
  when `ecs_enabled`, the HTTP API's `{proxy+}` integration switches from the Lambda to the VPC Link.
  **Verify (end of Phase 4):** `make up` → `make push-api` → smoke test passes and `/v1/health` reports `backend=ecs`.
  Then `make down`, confirm the ALB and ECS service are gone, `/v1/health` reports `backend=lambda`,
  and DynamoDB and S3 data remain.

---

## Phase 5 — Observability and cost visibility

- [ ] **P5.1 Module `observability`.** SNS topic `urbanmove-dev-alerts` with an email subscription (variable).
  CloudWatch dashboard `UrbanMove-dev` with rows:
  1) Ingest: `StationsFetched`, `ChangesEmitted`, `FetchErrors`, Lambda errors/duration
  2) Stream: alert processor errors and iterator age; showcase only: Kinesis `IncomingRecords`,
     `GetRecords.IteratorAgeMilliseconds`, `station_writer` errors, Firehose `DeliveryToS3.Success`
  3) State: `DataFreshnessSeconds`, DynamoDB consumed WCU/RCU and throttles, alerts created
  4) API: HTTP API count/4xx/5xx/latency p50/p95, API Lambda errors/duration; showcase only: ALB target 5xx and
     response time, `HealthyHostCount`, ECS CPU/memory, running task count
- [ ] **P5.2 Alarms → SNS** (stay within the 10 free alarms; showcase alarms are created only while their switch is on):
  data stale (`DataFreshnessSeconds` > 900 for 2 periods), ingest `FetchErrors` ≥ 3 in 15 min,
  DynamoDB throttled writes > 0 for 3 periods, alert processor iterator age > 600 s, any DLQ depth > 0,
  API 5xx rate > 1% (metric math), p95 latency > 1 s; showcase: Kinesis iterator age > 300 s, `HealthyHostCount` < 1.
  Treat missing data correctly per alarm (stale data = breaching).
- [ ] **P5.3 Tracing (light).** Powertools Tracer (X-Ray) on both Lambdas. API: optional ADOT sidecar behind a variable, off by default.
- [ ] **P5.4 `scripts/cost_report.py`.** Cost Explorer `GetCostAndUsage` month-to-date grouped by service and filtered
  by tag `Project=urbanmove` (activate the cost allocation tag first, a manual step). `make cost` prints a table.
  **Verify:** trigger an alarm on purpose (e.g. set the ingest schedule to an invalid URL for 10 minutes)
  and confirm the email arrives. Restore. Screenshot the dashboard into `docs/img/`.

---

## Phase 6 — CI/CD with OIDC

- [ ] **P6.1 `plan.yml`.** On PRs touching `infra/**`: assume `urbanmove-gha-plan` via OIDC, `terraform plan` for `envs/dev`,
  post a summary comment on the PR.
- [ ] **P6.2 `deploy.yml`.** On push to `main` (GitHub environment `dev` with Amruth as required reviewer):
  1) run CI, 2) `terraform apply` (Lambdas, including the API Lambda, are packaged by Terraform),
  3) run `smoke_test.sh` against the deployed endpoint and fail the job on error.
  When `ecs_enabled=true`, additionally build the ARM64 API image, tag it with the git sha, push to ECR, apply with
  `-var api_image_tag=<sha>`, and rely on the ECS circuit breaker to roll back. Skip these steps cleanly when off.
- [ ] **P6.3 Least-privilege deploy role.** Tighten `urbanmove-gha-deploy` to the resource ARNs the pipeline touches
  (prefix `urbanmove-dev-*`). Document the policy in `docs/SECURITY.md`.
  **Verify:** merge a trivial API change → pipeline deploys → `/v1/health` returns the new git sha.

---

## Phase 7 — Web map (frontend)

- [ ] **P7.1 `dashboard/`.** Static site (Vite + vanilla TS, or plain HTML + ES modules), Leaflet with OpenStreetMap tiles
  (include attribution). Stations drawn as circles colored by availability (empty / low / ok / full) with a toggle
  for bikes, e-bikes, or docks. Click a station for details. "Plan a trip" mode: click origin and destination,
  then show the recommended pickup and drop stations. Operators see an alerts panel.
  Login via Cognito managed login (auth code + PKCE, e.g. `oidc-client-ts`). Polls the API every 60 s.
  Credit Vélib' Métropole / Licence Ouverte and OpenStreetMap on the page.
- [ ] **P7.2 Module `frontend`.** Private S3 bucket plus CloudFront with OAC, default root object, security headers policy
  (HSTS, CSP allowing tiles and the API origin), `PriceClass_100`. `make deploy-web` builds, syncs, and invalidates.
  **Verify:** open the CloudFront URL, log in, see live stations, plan a trip.

---

## Phase 8 — Batch traffic analytics (Paris road sensors)

- [ ] **P8.1 Explore the source.** Paris Open Data dataset `comptages-routiers-permanents` (published daily, D-1,
  rolling 13 months, hourly counts per sensor arc). Confirm the API/export endpoint and field names
  (expected roughly: arc id, label, hour timestamp, flow `q`, occupancy `k`, traffic state, geo point/shape)
  from the dataset page and its attached notice, and record them in `docs/DATA_SOURCES.md`. Save a small fixture.
- [ ] **P8.2 `services/batch_traffic` Lambda.** Daily at 07:30 Europe/Paris (EventBridge Scheduler with timezone):
  download yesterday's records (paginate or use the export endpoint), write Parquet (pyarrow) to
  `raw/traffic/dt=YYYY-MM-DD/`, then run an Athena query building `curated/traffic_hotspots/dt=.../hotspots.json`:
  top 50 arcs by mean occupancy during 07–10h and 17–20h, with label, geometry, and mean flow.
  Glue table `raw_traffic` with partition projection.
- [ ] **P8.3 API endpoint.** `/v1/traffic/hotspots?date=` reads the curated JSON (cached). Add a hotspot layer to the web map.
  **Verify:** trigger the Lambda manually for yesterday, check the S3 objects and the Athena row counts, then curl the endpoint.

---

## Phase 9 — Scalability, resilience, disaster recovery

- [ ] **P9.1 Stream load test** (showcase day, `kinesis_enabled=true`). `services/simulator`: a CLI that pushes synthetic
  `StationChangedEvent`s (`synthetic=true`) to Kinesis at a configurable rate (e.g. 50 → 500 → 1,500 rec/s) for N minutes.
  Show where 1 shard saturates (`WriteProvisionedThroughputExceeded`), then rerun with `kinesis_shard_count=2`.
  Record `station_writer` iterator age and throughput. Switch off the same day.
- [ ] **P9.2 API load test.** `load/locustfile.py` (user or `service` token): mix of nearby, recommend, and stations calls.
  Headless run of 2–5 minutes ramping to ~200 users, **against both backends**: Lambda (free path; cold starts,
  concurrency) and ECS (showcase day; scaling 1 → N tasks). Compare latency and cost per million requests.
  Save charts and numbers in `docs/SCALABILITY.md`.
- [ ] **P9.3 DR configuration.** `enable_crr` → replication of `raw/` to `urbanmove-dev-lake-dr-<account>` in eu-west-1
  (versioned, its own lifecycle). AWS Backup plan for DynamoDB (daily, 7-day retention) on top of PITR.
  All modules parameterised by region so the stack can be planned in eu-west-1.
- [ ] **P9.4 DR drill and runbook.** `docs/RUNBOOK.md` covers: data stale, processor DLQ non-empty, API 5xx spike,
  table restore (PITR to a new table, then swap via a variable), and region failover (plan `envs/dev` with
  `region=eu-west-1`, point the ingester at the DR bucket). Run the PITR restore drill for real and record the timings.
  Stated objectives: **RTO 1 h** for the full stack, **RPO ≤ 5 min** for raw data in-region (one poll interval, or the
  Firehose buffer in showcase mode),
  ~15 min cross-region (CRR), and **RPO ≈ 0 for station state** (rebuildable from the live feed within one poll).
- [ ] **P9.5 Security hardening pass.** checkov hard-fail (with justified skips only), IAM Access Analyzer findings
  reviewed, no wildcard actions, S3 TLS-only, all logs with retention, image scan with no CRITICAL findings.
  Write `docs/SECURITY.md`: STRIDE threat model table (threat → mitigation → where in the code), IAM role matrix,
  encryption at rest and in transit, API protection (JWT, throttling, private ALB, SGs), secrets handling.

---

## Phase 10 — ML: short-term availability forecast (stretch, needs ≥ 3 weeks of data)

- [ ] **P10.1 Dataset.** Athena CTAS builds a training table per station at 5-minute resolution:
  features = hour, day of week, holiday flag (FR), bikes/ebikes/docks now, deltas over the last 15/30/60 min, capacity,
  station mean for the same hour last week. Target = bikes available in 30 min. Optionally add weather from Open-Meteo (no key).
- [ ] **P10.2 Model.** `ml/train.py`: time-based split (last week = test), LightGBM global model.
  Baselines: persistence (no change) and historical mean. Report MAE and also "empty in 30 min" precision/recall.
  **Only ship it if it beats persistence.** Model artifact plus metrics JSON go to S3 `models/<date>/` (versioned).
- [ ] **P10.3 Serving.** The API loads the latest model at startup. `GET /v1/stations/{id}/forecast?minutes=30`.
  The trip recommender uses predicted availability at arrival time when the model is present.
  A notebook or markdown report in `ml/REPORT.md` with honest results.

---

## Phase 11 — Portfolio packaging

- [ ] **P11.1 Architecture diagram** as code (`docs/diagram.py` using the `diagrams` library, exporting `docs/img/architecture.png`),
  showing security zones (public / private / managed services), data flows, and the DR region.
- [ ] **P11.2 README.md**: one-paragraph pitch, live-demo GIF, diagram, feature list, tech stack badges,
  "How it works" (ingest → stream → serve), key engineering decisions (link ADRs), scalability results,
  security summary, **cost table (actual numbers from `make cost`)**, DR objectives, run-it-yourself steps
  (`make setup` → bootstrap → `make apply` → `make up`), teardown, data attribution and licenses.
- [ ] **P11.3 Technical write-up** `docs/REPORT.md` (convertible to PDF), with sections: Introduction, System Architecture,
  Technology Stack, Implementation Process, Security Design, Scalability Strategy, Cost Analysis,
  Disaster Recovery Strategy, Lessons Learned.
- [ ] **P11.4 Demo.** 2–3 minute screen recording: map live, trip recommendation, operator alerts, CloudWatch dashboard,
  load test scaling, `make down`. Save it as a GIF for the README and the full video link.
- [ ] **P11.5 CV and LinkedIn.** Draft 2 CV bullets (EN and FR) with real numbers (events/day, p95 latency, cost/month,
  RTO/RPO) and a short LinkedIn post. Put them in `docs/PORTFOLIO_BLURBS.md`.
- [ ] **P11.6 Final teardown check.** `make down`, `make cost`, confirm only expected idle resources remain.

---

## Appendix — Expected idle cost

Free path only (`ingest_enabled=true`, `kinesis_enabled=false`, `ecs_enabled=false`): expect **~$0–2/month**
(S3 requests and storage, PITR on a tiny table, Athena scans). A showcase day with both switches on:
roughly **$2–3**. Budget plan for the $100 credits: free path for 6 months (~$10) + ~10 showcase days (~$30) leaves
a large margin. Always confirm with `make cost` after a few days of running.
