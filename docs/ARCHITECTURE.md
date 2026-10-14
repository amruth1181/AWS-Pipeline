# Architecture

> The diagram as code (`docs/diagram.py` → `docs/img/architecture.png`) is produced in P11.1.
> The ASCII overview is in `docs/IMPLEMENTATION.md` §0.

## 1. Components

| Layer | Component | AWS service | Notes |
|---|---|---|---|
| Sources | Vélib' GBFS | external HTTPS | live, ~1 min refresh |
| | Paris traffic sensors | external HTTPS | daily D-1 batch |
| | Simulator | container / CLI | synthetic load |
| Ingestion | Scheduler | EventBridge Scheduler | `rate(5 minutes)`; daily cron for traffic |
| | `ingest_velib` | Lambda (Python 3.12, ARM64) | diff vs last snapshot, conditional writes to DynamoDB, raw gzip JSONL to S3 |
| | Event stream *(showcase)* | Kinesis Data Streams | 1 shard, key = station_id; `kinesis_enabled` |
| Processing | `alert_processor` | Lambda (DynamoDB Streams ESM) | OLD vs NEW image → alerts, freshness metric |
| | `station_writer` *(showcase)* | Lambda (Kinesis ESM) | Kinesis → DynamoDB, same write function as the ingester |
| | Archive *(showcase)* | Kinesis Data Firehose | gzip JSON to S3, same partitions as the free path |
| | `batch_traffic` | Lambda | daily download, Parquet, Athena hotspots |
| Storage | Data lake | S3 | raw / curated / state / models; versioned; lifecycle |
| | Serving state | DynamoDB (provisioned, free tier) | `stations` (Streams on), `alerts` (TTL), PITR |
| | Catalog / SQL | Glue Data Catalog + Athena | partition projection, `velib_events` view, workgroup scan limit |
| Serving | API | FastAPI on Lambda (Mangum) | default backend |
| | API *(showcase)* | same FastAPI image on ECS Fargate | ARM64, 2 AZs, autoscaling 1–4; `ecs_enabled` |
| | Load balancer *(showcase)* | internal ALB | health checks on `/v1/health` |
| | Edge | API Gateway HTTP API (+ VPC Link in showcase) | HTTPS, JWT authorizer, throttling |
| | Identity | Cognito User Pool | users, `operators` group, M2M client |
| | Web map | S3 + CloudFront (OAC) | Leaflet, PKCE login |
| Ops | Observability | CloudWatch Logs/Metrics/Dashboards/Alarms, X-Ray, SNS | |
| | Cost | AWS Budgets, Cost Explorer (tags) | |
| | Delivery | GitHub Actions (OIDC), ECR, Terraform | |
| | DR | S3 CRR → eu-west-1, AWS Backup, PITR | |

## 2. Data flows

1. **Live path (free, always on).** Scheduler → `ingest_velib` fetches `station_status` and diffs it against
   `s3://lake/state/last_status.json.gz` → (a) conditional updates of changed stations in DynamoDB `stations`,
   (b) one gzip JSONL object of the changes to `s3://lake/raw/velib/dt=/hr=/`. DynamoDB Streams → `alert_processor` →
   `alerts` table + EMF metrics.
   **Showcase (`kinesis_enabled`):** the ingester `PutRecords` to Kinesis instead; `station_writer` applies the same
   conditional updates, Firehose archives to the same S3 layout. The alert path is unchanged.
2. **Serving path.** Client gets a Cognito token → HTTPS to the HTTP API (JWT checked, throttled) → API Lambda
   (or, with `ecs_enabled`, VPC Link → internal ALB → Fargate task) → app re-validates the JWT and checks group/scope →
   in-memory station cache (refreshed every 30 s) → response.
3. **Batch path.** Daily scheduler → `batch_traffic` → `raw/traffic/` Parquet → Athena query → `curated/traffic_hotspots/` → API.
4. **Analytics path.** Analyst → Athena workgroup → Glue tables over `raw/` and `curated/`.
5. **Delivery path.** GitHub → OIDC → deploy role → ECR push and `terraform apply` → ECS rolling deploy with circuit breaker.

## 3. Network and security zones

The VPC exists only in showcase mode (`ecs_enabled=true`). The free path is entirely serverless and outside any VPC.

```
VPC 10.20.0.0/16 (eu-west-3)
├── AZ a: public 10.20.0.0/24  | private 10.20.10.0/24
└── AZ b: public 10.20.1.0/24  | private 10.20.11.0/24
Gateway endpoints: S3, DynamoDB (free)
cost mode: Fargate tasks in public subnets (public IP for egress only, SG ingress = ALB SG only)
prod mode: Fargate tasks in private subnets, NAT GW for egress
Internal ALB: private subnets, SG ingress = VPC Link SG only
VPC Link: private subnets
```

| Zone | What lives there | Inbound allowed from |
|---|---|---|
| Internet edge (AWS managed) | HTTP API, CloudFront, Cognito managed login | Internet (HTTPS only) |
| Private app zone | ALB, ECS tasks | VPC Link → ALB → tasks (SG chaining) |
| Managed data zone | Kinesis, DynamoDB, S3, Firehose, Athena | IAM-authorized principals only; S3 TLS-only |
| Out-of-VPC compute | Lambdas | Invoked by AWS services only (no public URL) |

## 4. Security design (summary — full version in `docs/SECURITY.md`, P9.5)

- **Identity:** one IAM role per workload, scoped to resource ARNs. CI uses GitHub OIDC with branch and environment
  conditions. No static keys anywhere.
- **AuthN/AuthZ:** Cognito JWT checked at API Gateway and again in the app. `operators` group for alert endpoints.
  `urbanmove/read` scope for M2M.
- **Network:** no public ALB. SG chaining. Egress restricted to 443. Optional flow logs.
- **Encryption:** in transit, TLS at the edges plus AWS service endpoints over TLS, and S3 denies non-TLS requests.
  At rest, SSE on S3, Kinesis (KMS AWS-managed key), DynamoDB, CloudWatch Logs, and ECR.
- **API protection:** throttling (50 rps / burst 100), payload validation (pydantic), no stack traces in responses,
  `/docs` disabled in prod.
- **Supply chain:** ECR scan on push, pinned dependencies (uv lock), gitleaks pre-commit, checkov on Terraform.
- **Threats considered:** credential leakage, token forgery or replay, DoS on the API, poisoned feed data,
  over-privileged roles, cost exhaustion (budgets plus throttles plus reserved concurrency).

## 5. Scalability

- Ingestion is bounded by the source (~1,500 stations). In showcase mode Kinesis scales by shards and the writer scales
  with shards (one concurrent batch per shard, parallelization factor up to 10 if needed).
- DynamoDB uses free-tier provisioned capacity; writers rate-limit and retry throttles. Switching to on-demand is a
  one-line change if volume grows (ADR-009).
- The API is stateless apart from a soft cache. On Lambda it scales by concurrency; in showcase mode ECS target tracking
  on CPU and request count. The HTTP API scales automatically.
- Evidence comes from P9.1 and P9.2 load tests (`docs/SCALABILITY.md`).

## 6. High availability

- Multi-AZ: Lambda and all managed services are regional (multi-AZ by default). Showcase: ALB, ECS service and VPC Link subnets across 2 AZs.
- Regional managed services: Kinesis, DynamoDB, S3, Lambda, API Gateway, Cognito.
- Self-healing: ECS health checks, deployment circuit breaker with rollback, Lambda retries with bisect and DLQ.
- Graceful degradation: if ingestion stops, the API keeps serving the last known state and exposes `data_age_seconds`.

## 7. Disaster recovery

| Asset | Mechanism | RPO | RTO |
|---|---|---|---|
| Station state (DynamoDB) | PITR + daily AWS Backup; also rebuildable from the live feed | ≈ 0 (rebuild in one poll) | < 15 min |
| Raw history (S3) | Versioning + CRR to eu-west-1 | ≤ 5 min in-region / ~15 min cross-region | n/a (durable) |
| Infrastructure | Terraform, region-parameterised | n/a | ≤ 1 h (`apply` in eu-west-1) |
| Terraform state | Versioned S3 bucket | last apply | minutes |
| Users (Cognito) | Not replicated (accepted risk for a demo). Re-create test users with a script | — | — |

## 8. Cost model

See the cost switches in `docs/IMPLEMENTATION.md` and ADR-008. The account runs on the AWS Free plan ($100 credits until
2027-04-15), so the always-on path is designed to fit free allowances (~$0/month) and hourly resources only run in
showcase mode. Principles: pay-per-request or free-tier capacity by default, hourly resources behind flags,
log retention capped at 14 days, Athena scan limit, S3 lifecycle tiers, budget alerts, monthly `make cost` report in the README.
