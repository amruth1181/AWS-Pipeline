# Architecture Decision Records

Short ADRs. One per non-obvious choice. Template:

```
## ADR-NNN: Title
- Date: YYYY-MM-DD
- Status: accepted | superseded by ADR-xxx
- Context: why a decision was needed
- Decision: what we chose
- Alternatives: what else we considered, and why not
- Consequences: trade-offs, costs, follow-ups
```

---

## ADR-001: Kinesis Data Streams (provisioned, 1 shard) for ingestion — showcase mode only (see ADR-008)
- Date: 2026-10-14
- Status: accepted
- Context: Need a durable, ordered, replayable event stream with multiple consumers (processor and archive).
- Decision: Kinesis Data Streams, provisioned mode, 1 shard, 24 h retention. Partition key = `station_id`.
- Alternatives: MSK / MSK Serverless (Kafka, closest to prior experience, but the cost floor is far too high for a
  personal budget); SQS (no replay, no fan-out ordering); on-demand Kinesis (higher fixed hourly cost at low volume).
- Consequences: About €0.45/day while on. Scale by raising `kinesis_shard_count`. The load test (P9.1) documents the
  per-shard limit (1 MB/s or 1,000 rec/s write).

## ADR-002: Emit only changed stations (diff in the ingester)
- Status: accepted
- Context: Writing all ~1,500 stations every poll wastes Kinesis, Lambda and especially DynamoDB writes (cost).
- Decision: The ingester keeps the previous snapshot in S3 (`state/last_status.json.gz`) and emits only changed stations.
  The stream then carries change events (CDC semantics).
- Consequences: The raw archive holds changes, not full snapshots. Full state at time T = last event per station ≤ T
  (Athena window function). One extra S3 GET and PUT per poll (negligible).

## ADR-003: No NAT gateway in `cost` mode
- Status: accepted
- Context: A NAT gateway costs ~€1.1/day before data. Fargate tasks need egress to ECR and CloudWatch Logs.
  Interface VPC endpoints cost even more across 2 AZs.
- Decision: `network_mode = "cost"` runs tasks in public subnets with public IPs, but their security group accepts
  inbound **only** from the ALB security group, and the ALB is internal. S3 and DynamoDB use free gateway endpoints.
  `network_mode = "prod"` moves tasks to private subnets behind NAT.
- Consequences: Slightly larger attack surface on egress (tasks can reach the internet), no inbound exposure.
  Clearly documented as a cost trade-off, with the prod path available.

## ADR-004: Lambdas outside the VPC
- Status: accepted
- Context: The ingester needs the public internet (Vélib'). The processor only needs AWS APIs.
- Decision: Run both Lambdas outside the VPC. Security comes from IAM, not network placement.
- Alternatives: Lambdas in the VPC, which needs NAT or endpoints (cost) and adds cold-start ENI complexity.

## ADR-005: API Gateway HTTP API + VPC Link in front of an internal ALB
- Status: accepted
- Context: Need HTTPS without owning a domain, JWT validation at the edge, throttling, and a private backend.
- Decision: HTTP API (default HTTPS endpoint, Cognito JWT authorizer, stage throttling) → VPC Link → internal ALB → ECS.
- Alternatives: Public ALB with ACM (needs a domain); REST API (more features incl. WAF, but higher price);
  ALB + Cognito auth action (browser flows only, no M2M bearer tokens).
- Consequences: AWS WAF can't attach to HTTP APIs. Mitigation is throttling, JWT, and a private ALB. If WAF is needed
  later, put CloudFront + WAF in front.

## ADR-006: Read all stations with a cached Scan instead of a GSI
- Status: accepted
- Context: The API needs geo queries (nearby, bbox) over ~1,500 stations.
- Decision: The API Scans the stations table every 30 s into memory and does geo math in Python.
- Alternatives: Geohash GSI (doubles write cost on every update); OpenSearch or ElastiCache (hourly cost).
- Consequences: Fine up to tens of thousands of items. Revisit if the dataset grows.

## ADR-007: Terraform bootstrap with local state
- Status: accepted
- Context: The remote state bucket can't store its own creation state before it exists.
- Decision: `infra/bootstrap` uses local state (git-ignored, backed up manually). Everything else uses the S3 backend
  with `use_lockfile = true` (no DynamoDB lock table needed on Terraform ≥ 1.10).

## ADR-008: Hybrid architecture — free always-on path plus a switchable showcase mode
- Date: 2026-10-14
- Status: accepted (narrows ADR-001 and ADR-005 to showcase mode)
- Context: The account is on the AWS Free plan ($100 credits, expiring 2027-04-15). The original design costs
  ~$35–50/month (Kinesis shard, ALB, Fargate, public IPv4), which would use the credits in 2–3 months, and the live demo
  must survive after the credits end. Kinesis, ECS and ALB are still valuable to show in a portfolio.
- Decision: The always-on path is fully serverless and inside free allowances: Scheduler → `ingest_velib` Lambda →
  DynamoDB (+ raw gzip JSONL to S3) → DynamoDB Streams → `alert_processor` Lambda; API = FastAPI on Lambda (Mangum)
  behind the HTTP API. Two switches add the showcase path for load tests and demos: `kinesis_enabled` (Kinesis,
  Firehose, `station_writer`) and `ecs_enabled` (VPC, ALB, ECS Fargate, VPC Link). `make up` / `make down` toggle both.
- Alternatives: Original always-on Kinesis + ECS design (too expensive for the budget); pure free design (cheapest, but
  drops the stream and container story from the portfolio).
- Consequences: Two code paths for writing station state, kept identical by sharing `apply_station_changes()`.
  The FastAPI app needs two entry points (Lambda handler and container). Load tests can compare Lambda vs ECS.
  The free path costs ~$0–2/month; a showcase day costs ~$2–3.

## ADR-009: DynamoDB provisioned capacity in the free tier, with Streams carrying the previous state
- Date: 2026-10-14
- Status: accepted
- Context: On-demand DynamoDB is not covered by the always-free allowance, and ~1,500 station writes per poll would
  cost several dollars a month. The alert logic also needs each station's previous state, which the
  `StationChangedEvent` does not carry.
- Decision: Provisioned mode, stations 10 RCU / 15 WCU, alerts 5 RCU / 5 WCU (account total ≤ 25/25). Writers rate-limit
  and retry throttles. The stations table has DynamoDB Streams with `NEW_AND_OLD_IMAGES`. `alert_processor` reads OLD and
  NEW images to detect transitions. Lambda reads of DynamoDB Streams are free.
- Alternatives: On-demand (simple, but costs money at this write rate); adding `prev_*` fields to the event (couples the
  ingester to alert logic, and is wrong when events are replayed); `ReturnValues=ALL_OLD` in the writer (puts alert logic in
  two writers).
- Consequences: Burst writes can throttle. Burst capacity (~300 s of unused capacity) plus backoff absorbs a full poll,
  and P1.3 measures how many stations change per poll. Unchanged writes produce no stream record, so replays don't create
  duplicate alerts.

## ADR-010: ARM64 (Graviton) for all compute
- Date: 2026-10-14
- Status: accepted
- Context: The development machine is Apple Silicon (arm64). Lambda and Fargate both support ARM64.
- Decision: All Lambdas use `arm64`. The ECS task definition uses `ARM64`, and images are built for `linux/arm64`.
- Alternatives: x86_64 (default, but ~20% pricier and needs cross-builds from this Mac).
- Consequences: Lambda packages with native wheels (pydantic-core, pyarrow) must be built for `aarch64-manylinux`
  (`uv pip install --python-platform aarch64-manylinux2014`). CI builds images with Buildx for `linux/arm64`.

## ADR-011: API on Lambda by default, ECS Fargate behind a switch
- Date: 2026-10-14
- Status: accepted (amends ADR-005)
- Context: An internal ALB costs ~$18/month before any traffic, and Fargate tasks add more.
- Decision: The HTTP API integrates with a Lambda running the FastAPI app through Mangum. When `ecs_enabled=true`, the
  `{proxy+}` integration switches to VPC Link → internal ALB → ECS. JWT authorizer, throttling and routes are the same
  in both modes. `/v1/health` reports which backend served it.
- Consequences: The in-memory station cache lives per Lambda execution environment, so cold starts reload it. The ADR-005
  reasoning about the private ALB still applies in showcase mode.

## ADR-012: Synthetic events are filtered with an Athena view
- Date: 2026-10-14
- Status: accepted
- Context: In showcase mode, Firehose archives everything on the stream, including simulator events with `synthetic=true`.
  Those must not pollute analytics or ML training data.
- Decision: Keep one raw table, and expose the Athena view `velib_events` (`WHERE synthetic = false`). All named queries
  and the ML dataset read the view.
- Alternatives: A separate Kinesis stream for the simulator (another shard-hour cost); Firehose dynamic partitioning
  (extra per-GB charge).
- Consequences: Raw storage holds some synthetic data from load-test days (small). Analysts must use the view, not the table.

## ADR-013: No reserved concurrency on the ingester
- Date: 2026-10-14
- Status: accepted
- Context: The plan used reserved concurrency 1 to prevent overlapping polls. New accounts often have a regional
  concurrency limit of 10, and Lambda refuses any reservation that would leave fewer than 10 unreserved.
- Decision: No reservation. Overlap is prevented by design: Lambda timeout 60 s, poll interval 5 min, and Scheduler
  retries off. Conditional writes keep a rare overlap harmless anyway.
- Consequences: Works on a fresh account with no quota request.
