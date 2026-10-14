---
description: Check what is costing money right now and how to reduce it
---

1. If `scripts/cost_report.py` exists, run `make cost` (ask before running AWS commands if required by settings).
   Otherwise explain how to view month-to-date cost in Cost Explorer filtered by tag `Project=urbanmove`.
2. Read the current Terraform variables for `infra/envs/dev` and list every resource with an **hourly** charge that is
   currently enabled (showcase: Kinesis shards, Firehose, ALB, ECS tasks, public IPv4, NAT GW; plus interface endpoints, KMS CMKs, Container Insights, and anything above the free-tier ceilings).
3. Give a table: resource · on/off · rough €/day · how to turn it off (variable or `make down`).
4. Recommend the cheapest state that still fits what Amruth is doing this week. Don't change anything; just recommend.
