---
description: Safely switch off everything that costs money by the hour
---

1. Show what `make down` will remove by running `terraform plan` with `kinesis_enabled=false ecs_enabled=false`. Summarize the plan.
2. The free path costs ~$0, so pausing ingestion is rarely needed. Only if asked, set `ingest_enabled=false`, and mention that pausing creates a gap in the
   history used for the ML phase.
3. After he confirms, run the apply (it is in the `ask` list, so he approves it again).
4. Verify: no ALB (`aws elbv2 describe-load-balancers`), ECS service gone, and the Kinesis stream and Firehose are gone (`aws kinesis list-streams`).
5. Remind him that S3, DynamoDB, and Cognito are kept, and roughly what idle costs per month.

Never run `terraform destroy` or `make nuke` from here.
