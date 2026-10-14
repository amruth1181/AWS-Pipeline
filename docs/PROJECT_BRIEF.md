# Project brief — UrbanMove

## One-liner

A cloud-native, real-time smart-mobility platform for Paris on AWS. It ingests live Vélib' bike-share data and
Paris road-traffic sensors, processes them as a stream, and serves availability, congestion insights and
trip recommendations through a secured API and a live web map.

## Origin

Inspired by the EPITA *Cloud Computing* final-project brief ("Cloud Native Smart Mobility Platform", fictional
city authority *UrbanMove*). Rebuilt here as a **personal project** on real Paris open data, with the same
engineering bar: architecture quality, working implementation, security, and a technical report.

## Problem

Cities run shared mobility (bikes, scooters), public transport and road networks as separate systems.
Operators need a live, reliable view of supply and demand. Riders need to know where a bike or a free dock
will actually be. UrbanMove shows how to collect heterogeneous mobility data, process it in real time,
and expose it safely at low cost with high availability.

## Users

| User | Needs |
|---|---|
| Rider (web map / API) | Nearby bikes, e-bikes and docks; "best pickup and drop station for my trip" |
| Operator | Live alerts (stations empty, full, out of service), data freshness, system health |
| Analyst | Historical queries on all events (Athena), daily traffic hotspots |
| Partner service (M2M) | Read-only API access with client-credentials tokens |

## Functional requirements

1. **Real-time ingestion** of heterogeneous mobility data: Vélib' GBFS (live, ~1 min), Paris road sensors
   (daily batch), and a synthetic load generator.
2. **User service** via an authenticated REST API and a web map.
3. **Persistent storage**: an S3 data lake (raw and curated) plus DynamoDB serving state.
4. **Processing and analytics**: stream state transitions and alerts, Athena SQL analytics,
   daily traffic hotspots, and (stretch) an ML availability forecast.
5. **Authentication and authorization**: Cognito users and machine clients; role-based access (operators group);
   scope-based M2M access.
6. **Monitoring and observability**: structured logs, metrics, dashboard, alarms with notifications, tracing.

## Non-functional requirements

| Dimension | Target / approach |
|---|---|
| Scalability | Kinesis shards and Lambda scale with event rate; ECS autoscaling 1–4 tasks on CPU and request count; serverless storage |
| High availability | Multi-AZ ALB and ECS tasks; managed regional services (Kinesis, DynamoDB, S3, Lambda, API GW); health checks plus circuit-breaker rollback |
| Security | Least-privilege IAM per component, private ALB behind API GW and VPC Link, JWT auth, throttling, encryption at rest and in transit, no static CI keys (OIDC), IaC scanning |
| Cost | Pay-per-use first; hourly resources behind on/off switches; budget alerts; tag-based cost reporting |
| Observability | Dashboard covering ingest, stream, state and API; alarms on staleness, errors, latency and health |
| Disaster recovery | S3 versioning plus cross-region replication; DynamoDB PITR plus AWS Backup; state rebuildable from the live feed; region-parameterised IaC; RTO 1 h, RPO ≤ 5 min (raw, in-region) |

## Deliverables

- Public GitHub repo with all code and Terraform
- Architecture diagram (as code) showing components, flows, compute/storage layers, network and security zones, external integrations
- `docs/REPORT.md` technical report: Introduction, System Architecture, Technology Stack, Implementation Process,
  Security Design, Scalability Strategy, Cost Analysis, Disaster Recovery Strategy, Lessons Learned
- Deployment evidence: screenshots, demo GIF/video, load-test results, real cost numbers
- README written for recruiters and engineers

## Out of scope

Native mobile apps, payments, real vehicle hardware, multi-account AWS Organizations setup, Kubernetes
(ECS Fargate chosen instead; see ADRs).
